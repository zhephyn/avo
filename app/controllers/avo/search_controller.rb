require_dependency "avo/application_controller"

module Avo
  class SearchController < ApplicationController
    include Rails.application.routes.url_helpers
    include ActionView::Helpers::TextHelper

    before_action :set_resource_name, only: :show
    before_action :set_resource, only: :show

    def show
      render json: search_resources([resource], request:)
    rescue => error
      render_error error, _label: error.message
    end

    def process_results(results, request:)
      results
    end

    private

    def search_resources(resources, request: nil)
      process_results search_results(resources, request:), request:
    end

    def search_results(resources, request: nil)
      resources
        .map do |resource|
          # Apply authorization
          next unless @authorization.set_record(resource.model_class).authorize_action(
            :search,
            policy_class: resource.authorization_policy,
            raise_exception: false
          )

          search_resource resource
        end
        .select do |payload|
          payload.present?
        end
        .sort_by do |payload|
          payload.last[:count]
        end
        .reverse
        .to_h
    end

    def search_resource(resource)
      key = resource.name.pluralize.downcase

      # If search query is not defined return error in dev and nil otwherwise.
      if resource.search_query.blank?
        return nil unless render_error?

        search_query_undefined = error_payload(
          header: "⚠️ Warning ⚠️",
          help: "",
          _label: "Search is disabled for #{resource}.\n To enable it please use this guide...",
          _url: "https://docs.avohq.io/3.0/search.html#enable-search-for-a-resource"
        )

        return [key, search_query_undefined]
      end

      query = Avo::ExecutionContext.new(
        target: resource.search_query,
        params: params,
        q: params[:q].strip,
        query: resource.query_scope
      ).handle

      results_count, results = parse_results(query, resource)

      header = resource.plural_name

      if results_count > 0
        header = "#{header} (#{results_count})"
      end

      result_object = {
        header: header,
        help: resource.fetch_search(:help) || "",
        results: results,
        count: results.count
      }

      [key, result_object]
    end

    # When searching in a `has_many` association and will scope out the records against the parent record.
    # This is also used when looking for `belongs_to` associations, and this method applies the parents `attach_scope` if present.
    def apply_scope(query)
      if should_apply_has_many_scope?
        apply_has_many_scope
      elsif should_apply_attach_scope?
        apply_attach_scope(query, parent)
      end
    end

    # Parent passed as argument to be used as a variable instead of the method "def parent"
    # Otherwise parent = params...safe_constantize... will try to call method "def parent="
    def apply_attach_scope(query, parent)
      # If the parent is nil it probably means that someone's creating the record so it's not attached yet.
      # In these scenarios, try to find the grandparent for the new views where the parent is nil
      # and initialize the parent record with the grandparent attached so the user has the required information
      # to scope the query.
      # Example usage: Got to a project, create a new review, and search for a user.
      if parent.blank? && params[:via_parent_resource_id].present? && params[:via_parent_resource_class].present? && params[:via_relation].present?
        parent_resource_class = BaseResource.get_model_by_name params[:via_parent_resource_class]

        reflection_class = BaseResource.get_model_by_name params[:via_reflection_class]

        grandparent = parent_resource_class.find params[:via_parent_resource_id]
        parent = reflection_class.new(
          params[:via_relation] => grandparent
        )
      end

      Avo::ExecutionContext.new(target: attach_scope, query: query, parent: parent).handle
    end

    # This scope is applied if the search is being performed on a has_many association
    def apply_has_many_scope
      association_name = BaseResource.valid_association_name(parent, params[:via_association_id])

      # Get association records
      query = parent.send(association_name)

      # Apply policy scope if authorization is present
      query = resource.authorization&.apply_policy query

      if field&.scope&.present?
        query = Avo::ExecutionContext.new(target: field.scope, query:, parent:, resource:, parent_resource:).handle
      end

      Avo::ExecutionContext.new(target: @resource.class.search_query, params: params, query: query).handle
    end

    def apply_search_metadata(records, avo_resource)
      records.map do |record|
        resource = avo_resource.new(record: record)

        fetch_result_information record, resource, resource.class.fetch_search(:item, record: record)
      end
    end

    def fetch_result_information(record, resource, item)
      title = item&.dig(:title) || resource.record_title
      highlighted_title = highlight(title&.to_s, CGI.escapeHTML(params[:q] || ""))

      record_path = if resource.link_to_child_resource
        Avo.resource_manager.get_resource_by_model_class(record.class).new(record: record).record_path
      else
        resource.record_path
      end

      {
        _id: record.to_param,
        _label: highlighted_title,
        _url: resource.class.fetch_search(:result_path, record: resource.record) || record_path
      }
    end

    def should_apply_has_many_scope?
      params[:via_association] == "has_many" && @resource.class.search_query.present?
    end

    def should_apply_attach_scope?
      params[:via_association] == "belongs_to" && attach_scope.present?
    end

    def should_apply_any_scope?
      should_apply_has_many_scope? || should_apply_attach_scope?
    end

    def attach_scope
      @attach_scope ||= field&.attach_scope
    end

    def field
      @field ||= fetch_field
    end

    def parent
      @parent ||= fetch_parent
    end

    def fetch_field
      return if params[:via_association_id].nil?

      reflection_resource = parent_resource.new(
        view: Avo::ViewInquirer.new(params[:via_reflection_view]),
        record: parent,
        params: params,
        user: _current_user
      )

      reflection_resource.detect_fields.get_field(params[:via_association_id])
    end

    def fetch_parent
      return unless params[:via_reflection_id].present?

      parent_resource.find_record params[:via_reflection_id], params: params
    end

    def parent_resource
      @parent_resource ||= Avo.resource_manager.get_resource_by_model_class(params[:via_reflection_class])
    end

    def render_error(error, ...)
      raise error unless render_error?

      render json: {
        error: error_payload(...)
      }, status: 500
    end

    def error_payload(
      _label:,
      _url: "",
      header: "🚨 An error occurred during search 🚨",
      help: "Please review and resolve the issue before deployment 🚨"
    )
      {
        header:,
        help:,
        results: {
          _label:,
          _url:,
          _error: true
        },
        count: 1
      }
    end

    def search_results_count(resource)
      if resource.search_results_count
        Avo::ExecutionContext.new(
          target: resource.search_results_count,
          params: params
        ).handle
      else
        Avo.configuration.search_results_count
      end
    end

    def parse_results(query, resource)
      # When using custom search services query should return an array of hashes
      if query.is_a?(Array)
        # Apply highlight
        query.map do |result|
          result[:_label] = highlight(result[:_label].to_s, CGI.escapeHTML(params[:q] || ""))
        end

        # Force count to 0 until implement an API to pass the count
        results_count = 0

        # Apply the limit
        results = query.first(search_results_count(resource))
      else
        query = apply_scope(query) if should_apply_any_scope?

        # Get the count
        results_count = query.reselect(resource.model_class.primary_key).count

        # Get the results
        query = query.limit(search_results_count(resource))

        results = apply_search_metadata(query, resource)
      end

      [results_count, results]
    end

    def render_error?
      Rails.env.development?
    end
  end
end
