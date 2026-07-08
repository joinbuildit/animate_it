module AnimateIt
  class StudioController < ApplicationController
    def index
      AnimateIt.load_compositions!
      @compositions = AnimateIt.compositions
    end

    def show
      @composition = composition
      @compositions = AnimateIt.compositions
      @frame_base_url = animate_it_path("/compositions/#{@composition.id}/frame")
      @last_frame = @composition.duration_in_frames - 1
      @props_json = JSON.pretty_generate(@composition.props.defaults)
      @renders = RenderStore.all
    end
  end
end
