class Avo::Resources::CourseLink < Avo::BaseResource
  self.title = :link
  self.includes = [:course]
  self.model_class = Course::Link
  self.search = {
    query: -> {
      query
        .where("link ILIKE ?", "%#{params[:q]}%")
        .or(query.where(id: params[:q]))
    }
  }

  def display_fields
    field :id, as: :id
    field :link, as: :text, help: "Hehe. Something helpful."
    field :course, as: :belongs_to, searchable: true
  end

  def form_fields
    display_fields
    field :enable_course, as: :boolean, html: {
      edit: {
        input: {
          data: {
            action: "resource-edit#disable",
            resource_edit_disable_target_param: "courseBelongsToWrapper"
          }
        }
      }
    }
  end
end
