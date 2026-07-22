module ApplicationHelper
  def present(object, klass = nil)
    klass ||= "#{object.class}Presenter".constantize
    presenter = klass.new(object, self)
    yield presenter if block_given?
    presenter
  end

  def applicant_delete_enabled?
    Rails.application.config.x.applicant_delete_enabled
  end
end
