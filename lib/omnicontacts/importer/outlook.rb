require "omnicontacts/middleware/oauth2"
require "omnicontacts/parse_utils"
require "json"

# API Docs: https://msdn.microsoft.com/en-us/office/office365/api/api-catalog#Outlookcontacts
module OmniContacts
  module Importer
    class Outlook < Middleware::OAuth2
      include ParseUtils

      attr_reader :auth_host, :authorize_path, :auth_token_path, :scope

      def initialize app, client_id, client_secret, options ={}
        super app, client_id, client_secret, options
        @auth_host = "login.microsoftonline.com"
        @authorize_path = "/common/oauth2/v2.0/authorize"
        @scope = options[:permissions] || "https://outlook.office.com/contacts.read"
        @auth_token_path = "/common/oauth2/v2.0/token"
        @contacts_host = "graph.microsoft.com"
        @contacts_path = "/v1.0/me/contacts"
        @self_path = "/v1.0/me"
      end

      def fetch_contacts_using_access_token access_token, token_type
        fetch_current_user(access_token, token_type)
        contacts_response = https_get(@contacts_host, @contacts_path, {}, contacts_req_headers(access_token, token_type))
        contacts_from_response contacts_response
      end

      def fetch_current_user access_token, token_type
        self_response = https_get(@contacts_host, @self_path, {}, contacts_req_headers(access_token, token_type))
        user = current_user self_response
        set_current_user user
      end

      private

      def contacts_req_headers token, token_type
        { "Authorization" => "#{token_type} #{token}" }
      end

      def current_user me
        return nil if me.nil?
        me = JSON.parse(me)

        name_splitted = me["displayName"].split(" ")
        first_name = name_splitted.first
        last_name = name_splitted.last if name_splitted.size > 1

        user = empty_contact
        user[:id]         = me["id"]
        user[:email]      = me["mail"] || me["userPrincipalName"]
        user[:name]       = me["displayName"]
        # user[:first_name] = normalize_name(first_name)
        # user[:last_name]  = normalize_name(last_name)
        user[:first_name] = me["givenName"] || normalize_name(first_name)
        user[:last_name]  = me["surname"] || normalize_name(last_name)
        user
      end

      def contacts_from_response response_as_json
        response = JSON.parse(response_as_json)
        contacts = []
        response["value"].each do |entry|
          contact = empty_contact
          # Full fields reference:
          # https://msdn.microsoft.com/office/office365/api/complex-types-for-mail-contacts-calendar#RESTAPIResourcesContact
          contact[:id]         = entry["id"]
          contact[:first_name] = entry["givenName"]
          contact[:last_name]  = entry["surname"]
          contact[:name]       = entry["displayName"]
          contact[:email]      = parse_email(entry["emailAddresses"])
          contact[:birthday]   = birthday(entry["birthday"])

          address = [entry["homeAddress"], entry["businessAddress"], entry["otherAddress"]].reject(&:empty?).first
          if address
            contact[:address_1] = address["street"]
            contact[:city]      = address["city"]
            contact[:region]    = address["state"]
            contact[:postcode]  = address["postalCode"]
            contact[:country]   = address["countryOrRegion"]
          end

          contacts << contact if contact[:name] || contact[:first_name]
        end
        contacts
      end

      def empty_contact
        { :id => nil, :first_name => nil, :last_name => nil, :name => nil, :email => nil,
          :gender => nil, :birthday => nil, :profile_picture => nil, :address_1 => nil,
          :address_2 => nil, :city => nil, :region => nil, :postcode => nil, :relation => nil }
      end

      def parse_email emails
        return nil if emails.nil?
        emails.map! { |email| email["address"] }
        emails.select! { |email| valid_email? email }
        emails.first
      end

      def birthday dob
        return nil if dob.nil?
        birthday = dob[0..9].split("-")
        birthday[0] = nil if birthday[0].to_i < 1900 # if year is not set it returns 1604
        return birthday_format(birthday[1], birthday[2], birthday[0])
      end

      def valid_email? value
        /\A[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+\z/.match(value)
      end
    end
  end
end
