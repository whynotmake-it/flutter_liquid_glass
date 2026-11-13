part of 'flutter_gpu_geometry_renderer_native.dart';

/// The quads of one page as tile_vertex.glsl reads its instances: a
/// rectangle in clip space for a target of [_width] x [_height] texels, top
/// row first, with a value and a ramp. Rows count from [top], the first row
/// of the atlas being written.
final class _AtlasQuads {
  static const int bytesPerQuad = _quadFloats * 4;

  int _width = 1;
  int _height = 1;
  Float32List _floats = Float32List(256 * _quadFloats);
  int count = 0;

  /// The page row of the atlas's row 0.
  int top = 0;

  /// Starts the quads of a page of [width] x [height] texels.
  void reset(int width, int height) {
    _width = width;
    _height = height;
    count = 0;
    top = 0;
  }

  /// The quads written since [reset].
  ByteData get bytes => ByteData.sublistView(_floats, 0, count * _quadFloats);

  /// A fill quad over the texels [x], [y] to [x] + [w], [y] + [h]: its
  /// first texel gets ([v0], [v1], [v2], [v3]), and x and y step by a
  /// tile's texels (16 x [v2]) a texel from there; with looks the look in
  /// row [look] of the draw's block lies beside it, none where it is
  /// negative (tile_fill.glsl).
  void fill(
    int x,
    int y,
    int w,
    int h,
    double v0,
    double v1,
    double v2,
    double v3, {
    int look = -1,
  }) {
    final floats = _rect(x, y, w, h);
    final at = count * _quadFloats;
    floats[at + 4] = v0;
    floats[at + 5] = v1;
    floats[at + 6] = v2;
    floats[at + 7] = v3;
    floats[at + 8] = 128;
    floats[at + 9] = x.toDouble();
    floats[at + 10] = look.toDouble();
    floats[at + 11] = (top + y).toDouble();
    count++;
  }

  /// A strip over the texels [x], [y] to [x] + [w], [y] + [h], each [texel]
  /// buffer pixels a side with texel (0, 0) of the target at the buffer
  /// point ([bufferX], [bufferY]). A texel farther than [reach] from every
  /// shape's box is outside. The texels evaluate [members]
  /// ([TileRun.members]), which count from row [base] of the draw's block:
  /// each a row plus 16 where it starts its group, 32 past the last; or,
  /// where it lists none, the [count] rows from [base].
  void strip(
    int x,
    int y,
    int w,
    int h, {
    required double bufferX,
    required double bufferY,
    required int texel,
    required double reach,
    required int base,
    required int count,
    required int members,
  }) {
    final floats = _rect(x, y, w, h);
    final at = this.count * _quadFloats;
    floats[at + 4] = bufferX;
    floats[at + 5] = bufferY;
    floats[at + 6] = texel.toDouble();
    floats[at + 7] = reach;
    if (members == 0) {
      floats[at + 8] = 64.0 + base;
      floats[at + 9] = count.toDouble();
      floats[at + 10] = 0;
      floats[at + 11] = 0;
    } else {
      for (var slot = 0; slot < 4; slot++) {
        final byte = (members >> (8 * slot)) & 0xff;
        floats[at + 8 + slot] = byte == 0
            ? 32
            : base + (byte & 0x7f) - 1 + (byte & 0x80 != 0 ? 16 : 0);
      }
    }
    this.count++;
  }

  // Makes room for one more quad and writes its rectangle.
  Float32List _rect(int x, int y, int w, int h) {
    if ((count + 1) * _quadFloats > _floats.length) {
      _floats = Float32List(_floats.length * 2)..setAll(0, _floats);
    }
    final floats = _floats;
    final at = count * _quadFloats;
    final y0 = top + y;
    floats[at] = 2 * x / _width - 1;
    floats[at + 1] = 1 - 2 * y0 / _height;
    floats[at + 2] = 2 * (x + w) / _width - 1;
    floats[at + 3] = 1 - 2 * (y0 + h) / _height;
    return floats;
  }
}

/// The bytes a pass reads from the host, a page's quads and uniform blocks
/// and a field's staged texels, written at a cursor into host-visible
/// buffers.
///
/// The GPU reads a buffer when it runs the pass, not when the pass is
/// submitted, so bytes are written over only once every pass that reads
/// their buffer has run: a buffer counts its readers from the write to the
/// pass's completion ([_PassReads]). Counting frames instead, as
/// [gpu.HostBuffer] does, draws another frame's bytes whenever the GPU
/// falls further behind than the count, and an atlas drawn so is kept.
///
/// [gpu.HostBuffer] also fails an emplacement that starts inside a block
/// and runs past its end, which a variable number of quads does.
final class _GpuScratch {
  static const int _blockBytes = 1 << 17;
  static const int _texelBytes = 16;

  final List<_ScratchBuffer> _buffers = [];
  _ScratchBuffer? _current;

  /// How many buffers it holds.
  int get debugBuffers => _buffers.length;

  /// Writes [bytes] for a pass that counts the buffer among its [reads].
  gpu.BufferView write(ByteData bytes, _PassReads reads) {
    // A uniform block starts at the context's alignment, a field's staged
    // texels at a whole texel.
    final alignment = math.max(
      gpu.gpuContext.minimumUniformByteAlignment,
      _texelBytes,
    );
    final length = bytes.lengthInBytes;
    var buffer = _current;
    if (buffer == null || buffer.cursor + length > buffer.bytes.sizeInBytes) {
      buffer = _current = _unread(length) ?? _grow(length);
    }
    final offset = buffer.cursor;
    if (!buffer.bytes.overwrite(bytes, destinationOffsetInBytes: offset)) {
      throw StateError('Could not write $length bytes for an atlas pass.');
    }
    buffer.cursor = (offset + length + alignment - 1) ~/ alignment * alignment;
    reads.add(buffer);
    return gpu.BufferView(
      buffer.bytes,
      offsetInBytes: offset,
      lengthInBytes: length,
    );
  }

  // A buffer of [length] bytes or more that no pass still to run reads,
  // ready to be written from its start.
  _ScratchBuffer? _unread(int length) {
    for (final buffer in _buffers) {
      if (buffer.readers == 0 && buffer.bytes.sizeInBytes >= length) {
        buffer.cursor = 0;
        return buffer;
      }
    }
    return null;
  }

  _ScratchBuffer _grow(int length) {
    final buffer = _ScratchBuffer(
      gpu.gpuContext.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        math.max(length, _blockBytes),
      ),
    );
    _buffers.add(buffer);
    return buffer;
  }
}

final class _ScratchBuffer {
  _ScratchBuffer(this.bytes);

  final gpu.DeviceBuffer bytes;
  int cursor = 0;

  /// The writes into it that a pass still to run reads.
  int readers = 0;
}

/// The scratch buffers the pass being assembled reads.
final class _PassReads {
  final List<_ScratchBuffer> _buffers = [];

  void add(_ScratchBuffer buffer) {
    buffer.readers++;
    _buffers.add(buffer);
  }

  /// Hands the reads to the pass being submitted: the callback releases
  /// them once the GPU has run it.
  gpu.CompletionCallback<void> submitted() {
    final read = List.of(_buffers);
    _buffers.clear();
    return (_) => _release(read);
  }

  /// Releases the reads of a pass that was never submitted.
  void drop() {
    _release(_buffers);
    _buffers.clear();
  }

  static void _release(List<_ScratchBuffer> buffers) {
    for (final buffer in buffers) {
      buffer.readers--;
    }
  }
}
