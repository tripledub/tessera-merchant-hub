module NavigationHelper
  # Base classes shared by every primary nav link. Touch target is >= 44px tall.
  NAV_LINK_BASE = "flex items-center min-h-11 px-3 rounded-md text-sm font-medium transition-colors".freeze
  NAV_LINK_ACTIVE = "bg-indigo-50 text-indigo-700".freeze
  NAV_LINK_INACTIVE = "text-gray-600 hover:bg-gray-100 hover:text-gray-900".freeze

  # Renders a primary nav link, highlighting it when the current request is
  # within the given controller.
  def nav_link_to(label, path, controller:)
    active = controller_name == controller
    classes = "#{NAV_LINK_BASE} #{active ? NAV_LINK_ACTIVE : NAV_LINK_INACTIVE}"
    link_to label, path, class: classes, aria: { current: active ? "page" : nil }
  end
end
