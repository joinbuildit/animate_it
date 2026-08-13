require "securerandom"

module AnimateIt
  class RenderTicketStore
    PREFIX = "animate_it/render_tickets".freeze

    class << self
      def create!(composition:, props:)
        token = SecureRandom.urlsafe_base64(32, false)
        Rails.cache.write(
          key(token),
          { "composition" => composition.id, "props" => props.stringify_keys },
          expires_in: AnimateIt.config.render_ticket_ttl
        )
        raise Error, "AnimateIt internal rendering requires a shared, writable Rails cache" unless Rails.cache.read(key(token))

        token
      end

      def read(token)
        Rails.cache.read(key(token))
      end

      def delete(token)
        Rails.cache.delete(key(token))
      end

      private

      def key(token)
        "#{PREFIX}/#{token}"
      end
    end
  end
end
