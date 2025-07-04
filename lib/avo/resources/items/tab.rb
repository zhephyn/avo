class Avo::Resources::Items::Tab
  prepend Avo::Concerns::IsResourceItem

  include Avo::Concerns::HasItems
  include Avo::Concerns::HasItemType
  include Avo::Concerns::VisibleItems
  include Avo::Concerns::IsVisible
  include Avo::Concerns::VisibleInDifferentViews

  delegate :items, :add_item, to: :items_holder

  attr_accessor :description
  attr_reader :lazy_load

  def initialize(name: nil, description: nil, view: nil, **args)
    @name = name
    @description = description
    @items_holder = Avo::Resources::Items::Holder.new
    @view = Avo::ViewInquirer.new view
    @args = args
    @visible = args[:visible]
    @lazy_load = args[:lazy_load]

    post_initialize if respond_to?(:post_initialize)
  end

  def name
    Avo::ExecutionContext.new(target: @name).handle
  end

  def id
    name.to_s.parameterize
  end
  alias_method :to_param, :id

  def turbo_frame_id(parent: nil)
    digest_name = Digest::MD5.hexdigest(name)
    id = "#{Avo::Resources::Items::Tab.to_s.parameterize} #{digest_name}".parameterize
    return id if parent.nil?

    "#{parent.turbo_frame_id} #{id}".parameterize
  end

  class Builder
    include Avo::Concerns::BorrowItemsHolder

    delegate :field, to: :items_holder
    delegate :tool, to: :items_holder
    delegate :panel, to: :items_holder
    delegate :items, to: :items_holder

    def initialize(parent:, name: nil, **args)
      @tab = Avo::Resources::Items::Tab.new(name: name, **args)
      @items_holder = Avo::Resources::Items::Holder.new(parent: parent)
    end

    # Fetch the tab
    def build
      @tab.items_holder = @items_holder
      @tab
    end
  end
end
