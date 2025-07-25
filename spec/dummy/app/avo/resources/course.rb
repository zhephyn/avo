class Avo::Resources::Course < Avo::BaseResource
  self.search = {
    query: -> {
      TestBuddy.hi("params[:q]: '#{params[:q]}', q: '#{q}'") if Rails.env.test?
      query
        .where("name ILIKE ?", "%#{q}%")
        .or(query.where(id: q))
    }
  }
  self.keep_filters_panel_open = true
  self.stimulus_controllers = "city-in-country toggle-fields"
  # self.default_sort_column = :country
  self.translation_key = "test.translation_key.course"

  def show_fields
    fields_bag
    field :links, as: :has_many, searchable: true, placeholder: "Click to choose a link",
      discreet_pagination: true

    field :attendees, as: :array
  end

  def index_fields
    fields_bag
  end

  def form_fields
    fields_bag
  end

  def fields_bag
    field :id, as: :id
    field :name, as: :text, html: {
      edit: {
        input: {
          # classes: "bg-primary-500",
          data: {
            action: "input->resource-edit#debugOnInput"
          }
        },
        wrapper: {
          # style: "background: red;",
        }
      }
    }

    panel do
      field :has_skills, as: :boolean, filterable: true, html: -> do
        edit do
          input do
            # classes('block')
            data({
              # foo: record,
              # resource: resource,
              action: "input->resource-edit#toggle",
              resource_edit_toggle_target_param: "skills_textarea_wrapper",
              resource_edit_toggle_targets_param: ["skills_tags_wrapper"]
            })
          end
        end
      end

      # field :skills,
      #   as: :tags,
      #   fetch_values_from: "/admin/resources/users/get_users?hey=you&record_id=1", # {value: 1, label: "Jose"}
      #   format_using: -> {
      #     User.find(value).map do |user|
      #       {
      #         value: user.id,
      #         label: user.name
      #       }
      #     end
      #   }

      field :skills,
        as: :tags,
        disallowed: -> { record.skill_disallowed },
        suggestions: -> { record.skill_suggestions },
        html: -> do
          edit do
            wrapper do
              classes do
                unless record.has_skills
                  "hidden"
                end
              end
              # classes: "hidden"
            end
          end
        end
    end

    field :starting_at,
      as: :time,
      picker_format: "H:i",
      format: "HH:mm:ss z",
      timezone: -> { "Europe/Berlin" },
      picker_options: {
        hourIncrement: 1,
        minuteIncrement: 1,
        secondsIncrement: 1
      },
      filterable: true,
      relative: true

    field :country,
      as: :select,
      options: Course.countries.map { |country| [country, country] }.prepend(["-", nil]).to_h,
      html: {
        edit: {
          input: {
            data: {
              action: "city-in-country#onCountryChange"
            }
          }
        }
      }
    field :city,
      as: :select,
      options: Course.cities.values.flatten.map { |city| [city, city] }.to_h,
      display_value: false

    if params[:show_location_field] == '1'
      # Example for error message when resource is missing
      field :locations, as: :has_and_belongs_to_many
    end
  end

  def filters
    filter Avo::Filters::CourseCountryFilter
    filter Avo::Filters::CourseCityFilter
    filter Avo::Filters::StartingAt
  end

  def actions
    action Avo::Actions::ShowCurrentTime
  end
end
