module AnimateIt
  class Error < StandardError; end
  class CompositionNotFoundError < Error; end
  class CaptureError < Error; end
  class CaptureOperationalError < CaptureError; end
  class RenderPropsError < Error; end
end
