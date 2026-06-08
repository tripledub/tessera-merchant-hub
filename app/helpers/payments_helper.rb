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

  # Returns the payments_path with the given filter param (key+value) removed.
  # Handles multi-value params (e.g. status[]=succeeded&status[]=failed).
  # Always resets page to 1 by removing the page param.
  def filter_chip_remove_path(key, value)
    q = request.query_parameters.deep_dup
    key_s = key.to_s
    if q[key_s].is_a?(Array)
      remaining = Array(q[key_s]) - [value.to_s]
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
