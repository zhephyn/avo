# frozen_string_literal: true

class Avo::Views::ResourceIndexComponent < Avo::ResourceComponent
  include Avo::ResourcesHelper
  include Avo::ApplicationHelper

  prop :resource
  prop :resources
  prop :records, default: [].freeze
  prop :pagy
  prop :index_params, default: {}.freeze
  prop :filters, default: [].freeze
  prop :actions, default: [].freeze
  prop :reflection
  prop :turbo_frame, default: ""
  prop :parent_record
  prop :parent_resource
  prop :applied_filters, default: {}.freeze
  prop :query, reader: :public
  prop :scopes, reader: :public

  def title
    if @reflection.present?
      return name if field.present?

      reflection_resource.plural_name
    else
      @resource.plural_name
    end
  end

  # The Create button is dependent on the new? policy method.
  # The create? should be called only when the user clicks the Save button so the developers gets access to the params from the form.
  def can_see_the_create_button?
    # Disable creation for ArrayResources
    return false if @resource.resource_type_array?

    return authorize_association_for(:create) if @reflection.present?

    @resource.authorization.authorize_action(:new, raise_exception: false) && !has_reflection_and_is_read_only
  end

  def can_attach?
    return false if has_reflection_and_is_read_only

    reflection_class = if @reflection.is_a?(::ActiveRecord::Reflection::ThroughReflection)
      @reflection.through_reflection.class
    else
      @reflection.class
    end

    return false unless reflection_class.in? [
      ActiveRecord::Reflection::HasManyReflection,
      ActiveRecord::Reflection::HasAndBelongsToManyReflection
    ]

    authorize_association_for(:attach)
  end

  def create_path
    args = {}

    if @reflection.present?
      args = {
        via_resource_class: @parent_resource.class,
        via_relation_class: reflection_model_class,
        via_record_id: @parent_record.to_param
      }

      if @reflection.class.in? [
        ActiveRecord::Reflection::ThroughReflection,
        ActiveRecord::Reflection::HasAndBelongsToManyReflection
      ]
        args[:via_relation] = params[:resource_name]
      end

      if @reflection.is_a? ActiveRecord::Reflection::HasManyReflection
        args[:via_relation] = @reflection.name
      end

      if @reflection.inverse_of.present?
        args[:via_relation] = @reflection.inverse_of.name
      end
    end

    helpers.new_resource_path(resource: @resource, **args)
  end

  def attach_path
    current_path = CGI.unescape(request.env["PATH_INFO"]).split("/").select(&:present?)

    Avo.root_path(
      paths: [*current_path, "new"],
      query: {
        view: @parent_resource&.view&.to_s,
        turbo_frame: params[:turbo_frame],
        for_attribute: field&.try(:for_attribute)
      }.compact
    )
  end

  def singular_resource_name
    if @reflection.present?
      return name.singularize if field.present?

      reflection_resource.name
    else
      @resource.singular_name || @resource.model_class.model_name.name.downcase
    end
  end

  def description
    # If this is a has many association, the user can pass a description to be shown just for this association.
    return field&.description(query: @query) if @reflection.present?

    @resource.description
  end

  def show_search_input
    return false unless authorized_to_search?
    return false unless @resource.class.search_query.present?
    return false if field&.hide_search_input

    true
  end

  def authorized_to_search?
    # Hide the search if the authorization prevents it
    @resource.authorization.authorize_action("search", raise_exception: false)
  end

  def render_dynamic_filters_button
    return unless Avo.avo_dynamic_filters_installed?
    return unless @resource.has_filters?
    return if field&.hide_filter_button
    return if Avo::DynamicFilters.configuration.always_expanded

    a_button size: :sm,
      color: :primary,
      icon: "avo/filter",
      data: {
        controller: "avo-filters",
        action: "click->avo-filters#toggleFiltersArea",
        avo_filters_dynamic_filters_component_id_value: dynamic_filters_component_id
      } do
      Avo::DynamicFilters.configuration.button_label
    end
  end

  def scopes_list
    Avo::Advanced::Scopes::ListComponent.new(
      scopes: @scopes,
      resource: @resource,
      turbo_frame: @turbo_frame,
      parent_record: @parent_record,
      query: @query,
      loader: @resource.entity_loader(:scope)
    )
  end

  def can_render_scopes?
    defined?(Avo::Advanced)
  end

  def back_path
    # The `return_to` param takes precedence over anything else.
    return params[:return_to] if params[:return_to].present?

    # Show Go Back link only when association page is opened
    # as a standalone page
    if @reflection.present? && !helpers.turbo_frame_request?
      helpers.resource_path(record: @parent_record, resource: @parent_resource)
    end
  end

  private

  def reflection_model_class
    @reflection.active_record.to_s
  end

  def name
    field.custom_name? ? field.name : field.plural_name
  end

  def via_reflection
    return unless @reflection.present?

    {
      association: "has_many",
      association_id: @reflection.name,
      class: reflection_model_class,
      id: @parent_record.to_param,
      view: @parent_resource.view
    }
  end

  def header_visible?
    search_query_present? || filters_present? || has_many_view_types? || has_dynamic_filters?
  end

  def has_dynamic_filters?
    Avo.avo_dynamic_filters_installed? && @resource.has_filters?
  end

  def search_query_present?
    @resource.class.search_query.present?
  end

  def filters_present?
    @filters.present?
  end

  def has_many_view_types?
    @resource.available_view_types.count > 1
  end

  # Generate a unique component id for the current component.
  # This is used to identify the component in the DOM.
  def dynamic_filters_component_id
    @dynamic_filters_component_id ||= "dynamic_filters_component_id_#{SecureRandom.hex(3)}"
  end

  def reloadable
    field&.reloadable?
  end

  def linkable?
    field&.linkable?
  end
end
