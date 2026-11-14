part of 'flutter_gpu_geometry_renderer_native.dart';

/// The pages of the atlases that write one set of looks: every atlas placed
/// between two flushes shares one texture and is drawn in one pass, with one
/// submission, since each pass and each submission costs the UI thread
/// more than an atlas's quads do.
///
/// An atlas is placed when it is asked for: below the ones before it, laid
/// out to the page's width ([Tiling.layoutIn]), its quads written for the
/// page's size. So its image and its place are known at once, and [flush]
/// only draws. Atlases that outgrow the page go to a second one, drawn in a
/// pass of its own, and the pages grow to hold a flush like this one.
///
/// A pass clears and stores its whole target on a tiled GPU, and a texture
/// dropped may stay allocated until an old-generation GC. So every page
/// has one size, an eighth taller than the fullest flush needed, which
/// changes only when a flush outgrows it, at once, or once [_shrinkAfter]
/// flushes in a row would have fit in half of it. A page no renderer holds
/// an atlas in is a spare for later flushes, up to [_maxSpares] of them: a
/// page drawn every frame alternates between two.
final class _Pages {
  _Pages({
    required this._pipelines,
    required this._onePerTarget,
    required this._offsets,
    required int uniformSize,
    required this._fieldOffsets,
    required int fieldUniformSize,
    required this._lookCount,
  }) : _uniformData = ByteData(uniformSize),
       _fieldUniformData = ByteData(fieldUniformSize);

  static const int _maxSpares = 3;
  static const int _shrinkAfter = 30;

  final _TilePipelines _pipelines;
  final List<_TilePipelines>? _onePerTarget;
  final _GeometryUniformOffsets _offsets;
  final _TileFieldUniformOffsets _fieldOffsets;
  final int _lookCount;

  // The block the quads written next read, in rows of one shape or look.
  final ByteData _uniformData;
  late final Float32List _uniformFloats = _uniformData.buffer.asFloat32List();
  final ByteData _fieldUniformData;
  int _blockRows = 0;

  final _AtlasQuads _quads = _AtlasQuads();
  final List<_Draw> _draws = [];
  int _drawFrom = 0;
  _FieldDraw? _field;

  _Page? _open;
  final List<_Page> _spares = [];

  // The size of the pages.
  int _width = 0;
  int _height = 0;
  // What this flush has placed: the texels of its atlases, each laid out
  // on its own, and the widest of them; and how many of those texels are
  // in pages it has drawn already.
  int _texels = 0;
  int _widest = 0;
  int _drawnTexels = 0;
  // How many flushes in a row have filled no more than half a page, and
  // the most they placed.
  int _slack = 0;
  int _slackTexels = 0;
  int _slackWidest = 0;
  int _slackRows = 0;

  // The scratch buffers the open page's pass reads.
  final _PassReads _reads = _PassReads();

  gpu.BufferView _scratch(ByteData bytes) =>
      FlutterGpuGeometryRenderer._scratch.write(bytes, _reads);

  /// Places the atlas of [tiling] in the open page and writes its quads.
  (_Page, AtlasPlace) add(Tiling tiling, _FieldTextures fieldTextures) {
    final (page, layout, top) = _place(tiling);
    final quads = _quads..top = top;
    final looks = tiling.looks;
    final field = tiling.field;
    if (field != null) {
      final texture = _fieldTexture(fieldTextures, field.field, page);
      _packFieldUniforms(field, texture);
      _drawWith(_FieldDraw(_scratch(_fieldUniformData), texture));
    }

    const block = Tiling.size + 2;
    quads.fill(0, 0, block, block, kFarInward, 0, 0, 0);
    for (var look = 0; look < (looks?.count ?? 1); look++) {
      var row = -1;
      if (looks != null) {
        row = _takeRows(1);
        _packLook(looks, look, row);
      }
      quads.fill(
        (look + 1) * block,
        0,
        block,
        block,
        kDeepInward,
        0,
        0,
        0,
        look: row,
      );
    }
    final (tableX, tableY) = AtlasLayout.tableOrigin;
    final deeps = tiling.deeps;
    for (var i = 0; i < deeps.length; i += 5) {
      final (deepX, deepY) = AtlasLayout.deepEntryOf(deeps[i + 4]);
      quads.fill(
        tableX + deeps[i],
        tableY + deeps[i + 1],
        deeps[i + 2],
        deeps[i + 3],
        deepX.toDouble(),
        (top + deepY).toDouble(),
        0,
        1,
      );
    }
    final runs = tiling.runs;
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final (entryX, entryY) = layout.entryOf(i, 0);
      quads.fill(
        tableX + run.column,
        tableY + run.row,
        run.length,
        run.tall,
        entryX.toDouble(),
        (top + entryY).toDouble(),
        1 / run.texel,
        1,
      );
    }

    void strip(int i, {required double reach, int base = 0, int count = 0}) {
      final run = runs[i];
      final x = layout.strips[i * 2];
      final y = layout.strips[i * 2 + 1];
      final texel = run.texel;
      quads.strip(
        x,
        y,
        run.length * Tiling.size ~/ texel + 2,
        run.tall * Tiling.size ~/ texel + 2,
        bufferX: (run.column * Tiling.size - (x + 1) * texel).toDouble(),
        bufferY: (run.row * Tiling.size - (top + y + 1) * texel).toDouble(),
        texel: texel,
        reach: reach,
        base: base,
        count: count,
        members: field == null ? run.members : 0,
      );
    }

    if (field != null) {
      // A field takes its looks from its first set of shapes.
      var base = 0;
      var count = 0;
      if (looks != null && runs.isNotEmpty) {
        final members = tiling.shapeSets.first;
        count = math.min(members.length, geometryMaxShapesPerDraw);
        base = _takeRows(count);
        _packShapes(tiling.shapes, members, base, looks);
      }
      for (var i = 0; i < runs.length; i++) {
        strip(i, reach: 0, base: base, count: count);
      }
      _drawWith(null);
    } else {
      for (var set = 0; set < tiling.shapeSets.length; set++) {
        final members = tiling.shapeSets[set];
        final count = math.min(members.length, geometryMaxShapesPerDraw);
        final reach = tiling.reach.outward + _smoothing(tiling.shapes, members);
        var base = -1;
        for (var i = 0; i < runs.length; i++) {
          if (runs[i].shapes != set) continue;
          if (base < 0) {
            base = _takeRows(count);
            _packShapes(tiling.shapes, members, base, looks);
          }
          strip(i, reach: reach, base: base, count: count);
        }
      }
    }
    return (
      page,
      (
        tableX: tableX,
        tableY: top + tableY,
        width: page.width,
        height: page.height,
      ),
    );
  }

  // The open page with room for [tiling], its layout there and its top row.
  (_Page, AtlasLayout, int) _place(Tiling tiling) {
    final own = tiling.layout;
    _texels += own.width * own.height;
    _widest = math.max(_widest, own.width);
    var page = _open;
    if (page != null) {
      final layout = tiling.layoutIn(page.width);
      if (layout != null && page.rows + layout.height <= page.height) {
        final top = page.rows;
        page.rows += layout.height;
        return (page, layout, top);
      }
      // The flush outgrew its page: the atlases so far are drawn now, and
      // the pages from here on have room for them and this one.
      _drawnTexels = _texels - own.width * own.height;
      _draw();
    }
    final layout = _fit(tiling);
    page = _open = _take();
    if (!FlutterGpuGeometryRenderer._openPages.contains(this)) {
      FlutterGpuGeometryRenderer._openPages.add(this);
    }
    _quads.reset(page.width, page.height);
    page.rows = layout.height;
    return (page, layout, 0);
  }

  // The layout of [tiling] at the top of a new page, the pages growing to
  // hold what this flush has placed so far.
  AtlasLayout _fit(Tiling tiling) {
    // Up to twice as tall as wide the pages keep their width, so their
    // textures are replaced less often.
    if (tiling.layoutIn(_width) == null || _texels > 2 * _width * _width) {
      _width = math.min(AtlasLayout.maxSize, _squareWidth(_texels, _widest));
    }
    final layout = tiling.layoutIn(_width)!;
    final rows = layout.height + (_drawnTexels / _width).ceil();
    if (rows > _height) _height = _roomFor(rows);
    return layout;
  }

  // The width of a square page of [texels], no narrower than [widest].
  static int _squareWidth(int texels, int widest) =>
      math.max(widest, (math.sqrt(texels).ceil() + 31) & ~31);

  // A page of the capacity no scene still reads: a spare, or a new one.
  _Page _take() {
    final frame = FlutterGpuGeometryRenderer._completedFrames;
    _spares.removeWhere((spare) {
      if (spare.sized(_width, _height)) return false;
      spare.drop();
      return true;
    });
    final reusable = _spares.indexWhere(
      (spare) =>
          frame - spare.retiredFrame >=
          FlutterGpuGeometryRenderer.reuseAfterFrames,
    );
    if (reusable < 0) {
      return _Page(this, _width, _height, _lookCount)..begin();
    }
    assert(() {
      FlutterGpuGeometryRenderer.debugReusedTextureCount++;
      return true;
    }(), 'Count reused geometry textures in debug builds.');
    return _spares.removeAt(reusable)..begin();
  }

  // An eighth over [rows], in the 16 rows a tiled GPU stores at a time, so
  // atlases that grow a little keep their page's size and its textures.
  static int _roomFor(int rows) =>
      math.min(AtlasLayout.maxSize, (rows + (rows >> 3) + 15) & ~15);

  /// Lets go of one atlas in [page]: once none is held and the page is
  /// drawn, it is a spare.
  void release(_Page page) {
    page.leases--;
    if (page.leases == 0 && !page.open) _retire(page);
  }

  void _retire(_Page page) {
    page
      ..retiredFrame = FlutterGpuGeometryRenderer._completedFrames
      ..disposeImages();
    if (!page.sized(_width, _height)) {
      page.drop();
      return;
    }
    _spares.add(page);
    while (_spares.length > _maxSpares) {
      _spares.removeAt(0).drop();
    }
  }

  /// Draws the open page. Once [_shrinkAfter] flushes in a row have filled
  /// no more than half a page, the pages shrink to the fullest of them.
  void flush() {
    final page = _open;
    if (page == null) return;
    final texels = _texels;
    final widest = _widest;
    final rows = page.rows + (_drawnTexels / _width).ceil();
    _texels = 0;
    _widest = 0;
    _drawnTexels = 0;
    _draw();
    if (_roomFor(rows) * 2 > _height) {
      _forgetSlack();
      return;
    }
    _slackTexels = math.max(_slackTexels, texels);
    _slackWidest = math.max(_slackWidest, widest);
    _slackRows = math.max(_slackRows, rows);
    if (++_slack < _shrinkAfter) return;
    // Narrower too where the pages would be flatter than two to one.
    if (_roomFor(_slackRows) * 2 < _width) {
      _width = _squareWidth(_slackTexels, _slackWidest);
      _height = _roomFor((_slackTexels / _width).ceil());
    } else {
      _height = _roomFor(_slackRows);
    }
    _forgetSlack();
  }

  void _forgetSlack() {
    _slack = 0;
    _slackTexels = 0;
    _slackWidest = 0;
    _slackRows = 0;
  }

  /// Drops the spares and forgets the pages' size.
  void reset() {
    for (final spare in _spares) {
      spare.drop();
    }
    _spares.clear();
    _width = 0;
    _height = 0;
    _forgetSlack();
  }

  // Draws the open page's quads in one pass and submits it.
  void _draw() {
    final page = _open!;
    _open = null;
    _endDraw();
    try {
      final instances = _scratch(_quads.bytes);
      final corners = FlutterGpuGeometryRenderer._corners ??= gpu.BufferView(
        gpu.gpuContext.createDeviceBufferWithCopy(
          ByteData.sublistView(
            Float32List.fromList(const [0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1]),
          ),
        ),
        offsetInBytes: 0,
        lengthInBytes: 48,
      );
      // Where a pass takes one color attachment, an atlas with looks draws
      // its quads once for the geometry and once for each look, each pass
      // on a command buffer of its own as every pass here is; the first
      // carries the page's field copies, the last reports the reads.
      final onePerTarget = _lookCount == 0 ? null : _onePerTarget;
      final passes = onePerTarget == null ? 1 : _lookCount + 1;
      for (var target = 0; target < passes; target++) {
        final pipelines = onePerTarget == null
            ? _pipelines
            : onePerTarget[target];
        final commands =
            (target == 0 ? page.commands : null) ??
            gpu.gpuContext.createCommandBuffer();
        page.commands = null;
        final pass = commands.createRenderPass(
          onePerTarget == null ? page.renderTarget : page.renderTargets[target],
        )..setPrimitiveType(gpu.PrimitiveType.triangle);
        gpu.RenderPipeline? bound;
        for (final draw in _draws) {
          final field = draw.field;
          final pipeline = field == null ? pipelines.geometry : pipelines.field;
          if (!identical(pipeline, bound)) {
            // A binding outlives its draw, and a field's would bind over
            // the shapes of the draws after it.
            pass
              ..clearBindings()
              ..bindPipeline(bound = pipeline)
              ..bindVertexBuffer(corners);
          }
          if (field != null) {
            pass
              ..bindUniform(pipelines.fieldUniforms, field.uniforms)
              ..bindTexture(pipelines.fieldTexture, field.texture);
          }
          final slot = field == null
              ? pipelines.geometryShapes
              : pipelines.fieldShapes;
          if (slot != null) pass.bindUniform(slot, draw.shapes!);
          pass
            ..bindVertexBuffer(
              gpu.BufferView(
                instances.buffer,
                offsetInBytes:
                    instances.offsetInBytes +
                    draw.first * _AtlasQuads.bytesPerQuad,
                lengthInBytes: draw.count * _AtlasQuads.bytesPerQuad,
              ),
              slot: 1,
            )
            ..draw(6, instanceCount: draw.count);
        }
        if (target == passes - 1) {
          commands.submit(completionCallback: _reads.submitted());
        } else {
          commands.submit();
        }
      }
      assert(() {
        FlutterGpuGeometryRenderer.debugBatchedSubmitCount++;
        return true;
      }(), 'Count submitted pages in debug builds.');
    } finally {
      _reads.drop();
      _draws.clear();
      _drawFrom = 0;
      page.open = false;
      if (page.leases == 0) _retire(page);
    }
  }

  // The quads written next are drawn with [field], or with the shapes'
  // pipeline.
  void _drawWith(_FieldDraw? field) {
    if (identical(field, _field)) return;
    _endDraw();
    _field = field;
  }

  // Ends the draw of the quads written since the last, which read the
  // block as it is; the quads after them read a new one.
  void _endDraw() {
    final count = _quads.count - _drawFrom;
    if (count > 0) {
      final field = _field;
      _draws.add((
        first: _drawFrom,
        count: count,
        shapes: field == null || _pipelines.fieldShapes != null
            ? _scratch(_uniformData)
            : null,
        field: field,
      ));
      _drawFrom = _quads.count;
    }
    _blockRows = 0;
  }

  // The first of [count] rows of the block for the quads written next.
  int _takeRows(int count) {
    if (_blockRows + count > geometryMaxShapesPerDraw) _endDraw();
    final base = _blockRows;
    _blockRows += count;
    return base;
  }

  // Writes [look] of [looks] into [row] of the block.
  void _packLook(ShapeLooks looks, int look, int row) {
    final floats = _uniformFloats;
    final tints = _offsets.lookTints ~/ 4 + row * 4;
    final responses = _offsets.lookResponses ~/ 4 + row * 4;
    for (var i = 0; i < 4; i++) {
      floats[tints + i] = looks.looks[look * 8 + i];
      floats[responses + i] = looks.looks[look * 8 + 4 + i];
    }
  }

  // Writes [members] of [shapes], at most geometryMaxShapesPerDraw, into
  // the block's rows from [base], with their [looks] if any. The strips
  // name the rows they read, so the other rows hold whatever they held.
  void _packShapes(
    ShapeSet shapes,
    List<int> members,
    int base,
    ShapeLooks? looks,
  ) {
    final floats = _uniformFloats;
    final count = math.min(members.length, geometryMaxShapesPerDraw);
    const rows = geometryMaxShapesPerDraw * 12;
    final shapeAt = _offsets.shapeData ~/ 4 + base * 12;
    final rseAt = _offsets.rseData ~/ 4 + base * 12;
    // A pair's bottom half sits in the second half of uRseData.
    final lowerAt = rseAt + rows;
    final boundsAt = _offsets.shapeBounds ~/ 4 + base * 4;
    final lensAt = _offsets.shapeLens ~/ 4 + base * 4;
    for (var row = 0; row < count; row++) {
      final member = members[row];
      final from = member * 12;
      for (var i = 0; i < 12; i++) {
        floats[shapeAt + row * 12 + i] = shapes.shapes[from + i];
        floats[rseAt + row * 12 + i] = shapes.superellipses[from + i];
        floats[lowerAt + row * 12 + i] = shapes.superellipsesLower[from + i];
      }
      for (var i = 0; i < 4; i++) {
        floats[boundsAt + row * 4 + i] = shapes.boxes[member * 4 + i];
      }
      floats[lensAt + row * 4] = shapes.lensOf(member);
      floats[lensAt + row * 4 + 1] = shapes.turns[member];
      if (looks != null) _packLook(looks, looks.lookOf[member], base + row);
    }
  }

  // How far past the reach the blends of [members] can still pull a texel's
  // distance in: a quarter of each blend.
  static double _smoothing(ShapeSet shapes, List<int> members) {
    final count = math.min(members.length, geometryMaxShapesPerDraw);
    var smoothing = 0.0;
    for (var row = 0; row < count; row++) {
      final marker = shapes.shapes[members[row] * 12 + 11];
      if (marker > 0) smoothing += marker * 0.25;
    }
    return smoothing;
  }

  // The texture holding [field], its samples copied in ahead of [page]'s
  // pass.
  gpu.Texture _fieldTexture(
    _FieldTextures textures,
    LiquidGlassField field,
    _Page page,
  ) {
    final frame = FlutterGpuGeometryRenderer._completedFrames;
    final held = textures.held(field, frame);
    if (held != null) return held;
    if (FlutterGpuGeometryRenderer._uploadsShareCommandBuffer) {
      return textures.upload(
        field,
        frame,
        page.commands ??= gpu.gpuContext.createCommandBuffer(),
        _scratch,
      );
    }
    final upload = gpu.gpuContext.createCommandBuffer();
    final reads = _PassReads();
    try {
      return textures.upload(
        field,
        frame,
        upload,
        (bytes) => FlutterGpuGeometryRenderer._scratch.write(bytes, reads),
      );
    } finally {
      upload.submit(completionCallback: reads.submitted());
    }
  }

  void _packFieldUniforms(BufferField field, gpu.Texture texture) {
    final to = _fieldUniformData.buffer.asFloat32List();
    final offsets = _fieldOffsets;
    final (xx, xy, yx, yy, dx, dy) = field.bufferToGrid;
    final toGrid = offsets.bufferToGrid ~/ 4;
    to[toGrid] = xx;
    to[toGrid + 1] = xy;
    to[toGrid + 2] = yx;
    to[toGrid + 3] = yy;
    final shift = offsets.gridShift ~/ 4;
    to[shift] = dx;
    to[shift + 1] = dy;
    to[shift + 2] = field.distanceScale;
    final size = offsets.fieldSize ~/ 4;
    to[size] = field.field.cols.toDouble();
    to[size + 1] = field.field.rows.toDouble();
    to[size + 2] = 1 / texture.width;
    to[size + 3] = 1 / texture.height;
  }
}

/// One texture of atlases and the look textures beside it, with what one
/// use of it holds: the rows placed, the atlases renderers still hold.
///
/// The set of textures is fixed: Impeller's Vulkan backend keeps the
/// framebuffer of a pass on the texture of its first attachment and hands
/// it to the next pass that draws into that texture, whatever else that
/// pass draws into, so a page always draws with the same looks.
final class _Page {
  _Page(this.owner, int width, int height, int lookCount)
    : texture = _create(width, height),
      looks = List.unmodifiable([
        for (var i = 0; i < lookCount; i++) _create(width, height),
      ]) {
    renderTarget = gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(texture: texture, clearValue: _outsideEntry),
        for (final look in looks) gpu.ColorAttachment(texture: look),
      ],
    );
  }

  final _Pages owner;
  final gpu.Texture texture;

  /// Look textures of [texture]'s size.
  final List<gpu.Texture> looks;

  /// Clears the page to the outside tile's table entry, which the first
  /// atlas placed holds at that texel, and the looks to zero. Without a
  /// clear, texels no quad writes hold whatever the memory held: old
  /// mattes on the host, black or white streaks across glass on phones.
  late final gpu.RenderTarget renderTarget;

  /// The targets of the passes that write the page one color attachment a
  /// pass: the atlas, cleared as [renderTarget] clears it, then each look.
  late final List<gpu.RenderTarget> renderTargets = List.unmodifiable([
    gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(texture: texture, clearValue: _outsideEntry),
      ],
    ),
    for (final look in looks)
      gpu.RenderTarget(
        colorAttachments: [gpu.ColorAttachment(texture: look)],
      ),
  ]);

  static final vm.Vector4 _outsideEntry = vm.Vector4(
    AtlasLayout.outsideEntry.$1.toDouble(),
    AtlasLayout.outsideEntry.$2.toDouble(),
    0,
    1,
  );

  int get width => texture.width;
  int get height => texture.height;

  bool sized(int width, int height) =>
      texture.width == width && texture.height == height;

  /// The handles of this use of the page, disposed with its last atlas:
  /// new ones each use, so what compares images sees that the page holds
  /// other atlases, and what draws with a released atlas fails.
  late ui.Image image;
  List<ui.Image> lookImages = const [];

  /// Rows placed, the atlases renderers hold, and whether it is yet to be
  /// drawn.
  int rows = 0;
  int leases = 0;
  bool open = false;

  /// Frame count when the last atlas held was released.
  int retiredFrame = 0;

  /// What copies fields in ahead of the pass, where one is recorded.
  gpu.CommandBuffer? commands;

  /// Starts a use of the page.
  void begin() {
    image = texture.asImage();
    lookImages = List.unmodifiable([for (final look in looks) look.asImage()]);
    _hasImages = true;
    rows = 0;
    open = true;
  }

  /// Gives the page up.
  void drop() {
    disposeImages();
    assert(() {
      FlutterGpuGeometryRenderer.debugDroppedTextureCount += 1 + looks.length;
      return true;
    }(), 'Count dropped geometry textures in debug builds.');
  }

  bool _hasImages = false;

  /// Disposes the handles of the use that ended.
  void disposeImages() {
    if (!_hasImages) return;
    _hasImages = false;
    image.dispose();
    for (final look in lookImages) {
      look.dispose();
    }
    lookImages = const [];
  }

  static gpu.Texture _create(int width, int height) {
    assert(() {
      FlutterGpuGeometryRenderer.debugAllocatedTextureCount++;
      return true;
    }(), 'Count allocated geometry textures in debug builds.');
    return gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
    );
  }
}
