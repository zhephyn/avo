# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Post comments use_resource PhotoComment", type: :feature do
  let!(:post) { create :post, user: admin }
  let!(:comments) { create_list :comment, 20, commentable: post }
  let!(:comment) { create :comment, user: admin }

  describe "tests" do
    it "if have different fields from original comment resource" do
      visit_page

      expect(page).to have_text("Photo comments")
      expect(page).to have_text("Tiny name")
      expect(page).to have_text("Photo")
      expect(page).to have_link("Create new photo comment")
      expect(page).to have_link("Attach photo comment")

      expect(page).not_to have_text("Posted at")
      expect(page).not_to have_text("Create new comment")
    end

    it "if create new photo comment persist and attach" do
      visit_page

      click_on "Create new photo comment"

      expect(page).to have_current_path "/admin/resources/photo_comments/new?via_record_id=#{post.slug}&via_relation=commentable&via_relation_class=Post&via_resource_class=Avo%3A%3AResources%3A%3APost"

      fill_in "comment_body", with: "I'm a photo comment!"

      save

      expect(current_path).to eql "/admin/resources/posts/#{post.slug}"

      comment = post.comments.last

      visit "/admin/resources/photo_comments/#{comment.id}"

      expect(page).to have_text("I'm a photo comment!")
    end

    it "if have photo comment resource controls" do
      visit_page

      expect(page).to have_selector "[title='Edit photo comment']"
      expect(page).to have_selector "[title='View photo comment']"
      expect(page).to have_selector "[title='Delete photo comment']"
    end

    it "applies on belongs to" do
      visit "admin/resources/comments/#{comment.id}"

      expect(page).to have_link comment.user.name,
        href: "/admin/resources/compact_users/#{comment.user.slug}?via_record_id=#{comment.to_param}&via_resource_class=Avo%3A%3AResources%3A%3AComment"

      click_on comment.user.name
      expect(page).to have_current_path "/admin/resources/compact_users/#{comment.user.slug}?via_record_id=#{comment.to_param}&via_resource_class=Avo%3A%3AResources%3A%3AComment"

      expect(page).to have_text "Personal information"
      expect(page).to have_text "Contact"
    end
  end
end

def visit_page
  visit "admin/resources/posts/#{post.id}/comments?turbo_frame=has_many_field_show_photo_comments"

  expect(current_path).to eql "/admin/resources/posts/#{post.id}/comments"
end
