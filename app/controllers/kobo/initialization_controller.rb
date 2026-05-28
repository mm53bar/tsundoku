module Kobo
  # GET /kobo/:handle/v1/initialization
  # Returns the Resources dictionary the device uses to discover all
  # other API endpoints (image host, library sync, library metadata,
  # etc.). Without this, newer Kobo firmware fails before even calling
  # /v1/library/sync — the "Something went wrong" message lands here.
  #
  # Most resources are kept at their Kobo defaults (the device will
  # request them and we return {} via the catch-all, which is fine).
  # We override the ones that matter for sync to work:
  #   image_host, image_url_template, image_url_quality_template,
  #   library_sync.
  class InitializationController < BaseController
    NATIVE_RESOURCES = JSON.parse(Rails.root.join("lib/data/kobo_native_resources.json").read).freeze

    def show
      resources = NATIVE_RESOURCES.merge(
        "image_host"                 => request.base_url,
        "image_url_template"         => "#{request.base_url}/kobo/#{params[:handle]}/{ImageId}/{Width}/{Height}/false/image.jpg",
        "image_url_quality_template" => "#{request.base_url}/kobo/#{params[:handle]}/{ImageId}/{Width}/{Height}/{IsGreyscale}/image.jpg",
        "library_sync"               => "#{request.base_url}/kobo/#{params[:handle]}/v1/library/sync"
      )

      # x-kobo-apitoken: e30= — base64 of "{}". Calibre-web sets this; the
      # device may key off its presence.
      response.set_header("x-kobo-apitoken", "e30=")
      render json: { "Resources" => resources }
    end
  end
end
