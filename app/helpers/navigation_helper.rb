module NavigationHelper
  # Sidebar nav link — uses TailAdmin menu-item utilities.
  # Touch target is >= 44px (min-h-11) for Hotwire Native compatibility.
  def nav_link_to(label, path, controller:, icon: nil)
    active = controller_name == controller
    state  = active ? "menu-item-active" : "menu-item-inactive"

    link_to path, class: "menu-item #{state} group min-h-11", aria: { current: active ? "page" : nil } do
      concat icon_tag(icon, active: active) if icon
      concat content_tag(:span, label, class: "menu-item-text")
    end
  end

  private

  def icon_tag(name, active:)
    state = active ? "menu-item-icon-active" : "menu-item-icon-inactive"
    content_tag(:span, class: "h-5 w-5 flex-shrink-0 #{state}") do
      render "shared/icons/#{name}"
    end
  rescue ActionView::MissingTemplate
    # Icon partial not yet created — renders nothing rather than erroring
    "".html_safe
  end
end
