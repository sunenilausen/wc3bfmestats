module PlayerRelationshipsHelper
  def sortable_header(label, column, table)
    sort_param = "#{table}_sort"
    direction_param = "#{table}_direction"

    current_sort = params[sort_param] || "total"
    current_direction = params[direction_param] || "desc"

    is_current = current_sort == column
    new_direction = is_current && current_direction == "desc" ? "asc" : "desc"

    arrow = if is_current
      current_direction == "asc" ? " ▲" : " ▼"
    else
      ""
    end

    # Preserve the other table's sort params
    new_params = {
      allies_sort: params[:allies_sort] || "total",
      allies_direction: params[:allies_direction] || "desc",
      rivals_sort: params[:rivals_sort] || "total",
      rivals_direction: params[:rivals_direction] || "desc"
    }
    new_params[sort_param.to_sym] = column
    new_params[direction_param.to_sym] = new_direction

    link = link_to(
      "#{label}#{arrow}".html_safe,
      player_relationships_path(@player, new_params),
      class: "hover:text-blue-600 #{is_current ? 'text-blue-600 font-bold' : ''}"
    )

    content_tag(:th, link, class: "px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase cursor-pointer hover:bg-gray-100")
  end
end
