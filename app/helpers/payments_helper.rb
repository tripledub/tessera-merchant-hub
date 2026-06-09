module PaymentsHelper
  # Human-readable label for a filter chip.
  # key is a Symbol or String (:status, :date_from, etc.)
  # value is the raw param value string.
  def filter_chip_label(key, value)
    case key.to_sym
    when :status     then "Status: #{value.humanize}"
    when :date_from  then "From: #{value}"
    when :date_to    then "To: #{value}"
    when :reference  then "Ref: #{value}"
    when :amount_min then "Min: #{value}"
    when :amount_max then "Max: #{value}"
    else "#{key}: #{value}"
    end
  end

  # Renders a sortable <th> cell.
  # column: the sort param key (e.g. "amount") or nil for unsortable columns.
  # current_params: request params hash — used to build the sort URL preserving other filters.
  #
  # Sortable columns show up/down triangle indicators (from TailAdmin data-table-03.html).
  # The active direction triangle is highlighted (fill-brand-500); inactive is muted.
  def sort_th(label, column, current_params)
    base_class = "px-4 py-3 text-left text-theme-xs font-medium text-gray-700 dark:text-gray-400 border-r border-gray-200 dark:border-gray-800 last:border-r-0"

    unless column
      return content_tag(:th, label, class: base_class)
    end

    active       = current_params[:sort] == column
    current_dir  = current_params[:direction] || "desc"
    next_dir     = (active && current_dir == "asc") ? "desc" : "asc"
    sort_params  = current_params.to_unsafe_h.except("sort", "direction", "page").merge(sort: column, direction: next_dir)
    url          = payments_path(sort_params)

    up_class   = (active && current_dir == "asc")  ? "fill-brand-500" : "fill-gray-300 dark:fill-gray-700"
    down_class = (active && current_dir == "desc") ? "fill-brand-500" : "fill-gray-300 dark:fill-gray-700"

    content_tag(:th, class: base_class) do
      link_to url, class: "flex items-center gap-2 hover:text-gray-900 dark:hover:text-white",
                   data: { turbo_frame: "payments-table", turbo_action: "advance" } do
        concat(label)
        concat(content_tag(:span, class: "flex flex-col gap-0.5") do
          # Up triangle (ascending indicator)
          concat(content_tag(:svg, class: up_class, width: "8", height: "5", viewBox: "0 0 8 5",
                              fill: "none", xmlns: "http://www.w3.org/2000/svg") do
            content_tag(:path,
              d: "M4.40962 0.585167C4.21057 0.300808 3.78943 0.300807 3.59038 0.585166L1.05071 4.21327C0.81874 4.54466 1.05582 5 1.46033 5H6.53967C6.94418 5 7.18126 4.54466 6.94929 4.21327L4.40962 0.585167Z",
              fill: "")
          end)
          # Down triangle (descending indicator)
          concat(content_tag(:svg, class: down_class, width: "8", height: "5", viewBox: "0 0 8 5",
                              fill: "none", xmlns: "http://www.w3.org/2000/svg") do
            content_tag(:path,
              d: "M4.40962 4.41483C4.21057 4.69919 3.78943 4.69919 3.59038 4.41483L1.05071 0.786732C0.81874 0.455343 1.05582 0 1.46033 0H6.53967C6.94418 0 7.18126 0.455342 6.94929 0.786731L4.40962 4.41483Z",
              fill: "")
          end)
        end)
      end
    end
  end

  # Returns the payments_path with the given filter param (key+value) removed.
  # Handles multi-value params (e.g. status[]=succeeded&status[]=failed).
  # Always resets page to 1 by removing the page param.
  def filter_chip_remove_path(key, value)
    q = request.query_parameters.deep_dup
    key_s = key.to_s
    if q[key_s].is_a?(Array)
      remaining = Array(q[key_s]) - [ value.to_s ]
      if remaining.any?
        q[key_s] = remaining
      else
        q.delete(key_s)
      end
    else
      q.delete(key_s)
    end
    q.delete("page")
    payments_path(q)
  end
end
