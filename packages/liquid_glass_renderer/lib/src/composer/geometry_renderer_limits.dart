/// The most shapes one draw of the matte evaluates (MAX_SHAPES in the
/// geometry shaders).
///
/// A layer draws this many glass shapes in one cluster, the shapes whose
/// edges reach the same 16-pixel tile of the layer, and any number of
/// clusters; a field whose shapes carry their own appearances is one draw, so
/// it holds this many in all. Shapes beyond it are not drawn and debug builds
/// print a warning. Split the glass across several layers to draw more.
const int geometryMaxShapesPerDraw = 16;
