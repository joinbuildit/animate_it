module AnimateIt
  class PropsController < ApplicationController
    def update
      @composition = composition
      @props_json = JSON.pretty_generate(@composition.props.resolve(preview_props))
      @frame_url = "#{animate_it_path("/compositions/#{@composition.id}/frame/0")}?#{URI.encode_www_form(pp: "disable",
                                                                                                         props_json: @props_json)}"
    end
  end
end
