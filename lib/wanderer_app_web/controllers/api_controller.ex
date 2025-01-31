defmodule WandererAppWeb.APIController do
  use WandererAppWeb, :controller

  import Ash.Query, only: [filter: 2]

  alias WandererApp.Api
  alias WandererApp.MapSystemRepo
  alias WandererApp.MapCharacterSettingsRepo
  alias WandererApp.Api.Character
  alias WandererApp.CachedInfo


# -----------------------------------------------------------------
# Common
# -----------------------------------------------------------------

  @doc """
  GET /api/system-static-info

  Requires 'id' (the solar_system_id)

  Example:
      GET /api/common/system_static?id=31002229
      GET /api/common/system_static?id=31002229
  """
  def show_system_static(conn, params) do
    with {:ok, solar_system_str} <- require_param(params, "id"),
         {:ok, solar_system_id} <- parse_int(solar_system_str) do
      case CachedInfo.get_system_static_info(solar_system_id) do
        {:ok, system} ->
          data = static_system_to_json(system)
          json(conn, %{data: data})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "System not found"})
      end
    else
      {:error, msg} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: msg})
    end
  end

# -----------------------------------------------------------------
# Map
# -----------------------------------------------------------------

@doc """
GET /api/map/systems

Requires either `?map_id=<UUID>` **OR** `?slug=<map-slug>` in the query params.

If `?all=true` is provided, **all** systems are returned.
Otherwise, only "visible" systems are returned.

Examples:
    GET /api/map/systems?map_id=466e922b-e758-485e-9b86-afae06b88363
    GET /api/map/systems?slug=my-unique-wormhole-map
    GET /api/map/systems?map_id=<UUID>&all=true
"""
def list_systems(conn, params) do
  with {:ok, map_id} <- fetch_map_id(params) do
    # Decide which function to call based on the "all" param
    repo_fun =
      if params["all"] == "true" do
        &MapSystemRepo.get_all_by_map/1
      else
        &MapSystemRepo.get_visible_by_map/1
      end

    case repo_fun.(map_id) do
      {:ok, systems} ->
        data = Enum.map(systems, &map_system_to_json/1)
        json(conn, %{data: data})

      {:error, reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Could not fetch systems for map_id=#{map_id}: #{inspect(reason)}"})
    end
  else
    {:error, msg} ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: msg})
  end
end


  @doc """
  GET /api/map/system

  Requires 'id' (the solar_system_id)
  plus either ?map_id=<UUID> or ?slug=<map-slug>.

  Example:
      GET /api/map/system?id=31002229&map_id=466e922b-e758-485e-9b86-afae06b88363
      GET /api/map/system?id=31002229&slug=my-unique-wormhole-map
  """
  def show_system(conn, params) do
    with {:ok, solar_system_str} <- require_param(params, "id"),
         {:ok, solar_system_id} <- parse_int(solar_system_str),
         {:ok, map_id} <- fetch_map_id(params) do
      case MapSystemRepo.get_by_map_and_solar_system_id(map_id, solar_system_id) do
        {:ok, system} ->
          data = map_system_to_json(system)
          json(conn, %{data: data})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "System not found in map=#{map_id}"})
      end
    else
      {:error, msg} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: msg})
    end
  end



  @doc """
  GET /api/map/tracked_characters_with_info

  Example usage:
    GET /api/map/tracked_characters_with_info?map_id=<uuid>
    GET /api/map/tracked_characters_with_info?slug=<map-slug>

  Returns a list of tracked records, plus their fully-loaded `character` data.
  """
  def tracked_characters_with_info(conn, params) do
    with {:ok, map_id} <- fetch_map_id(params),
         {:ok, settings_list} <- get_tracked_by_map_ids(map_id),
         {:ok, char_list} <-
           read_characters_by_ids_wrapper(Enum.map(settings_list, & &1.character_id)) do

      chars_by_id = Map.new(char_list, &{&1.id, &1})

      data =
        Enum.map(settings_list, fn setting ->
          found_char = Map.get(chars_by_id, setting.character_id)

          %{
            id: setting.id,
            map_id: setting.map_id,
            character_id: setting.character_id,
            tracked: setting.tracked,
            inserted_at: setting.inserted_at,
            updated_at: setting.updated_at,
            character:
              if found_char do
                character_to_json(found_char)
              else
                %{}
              end
          }
        end)

      json(conn, %{data: data})
    else
      {:error, :get_tracked_error, reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No tracked records found for map_id: #{inspect(reason)}"})

      {:error, :read_characters_by_ids_error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Could not load Character records: #{inspect(reason)}"})

      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  defp get_tracked_by_map_ids(map_id) do
    case MapCharacterSettingsRepo.get_tracked_by_map_all(map_id) do
      {:ok, settings_list} ->
        {:ok, settings_list}

      {:error, reason} ->
        {:error, :get_tracked_error, reason}
    end
  end

  defp read_characters_by_ids_wrapper(ids) do
    case read_characters_by_ids(ids) do
      {:ok, char_list} ->
        {:ok, char_list}

      {:error, reason} ->
        {:error, :read_characters_by_ids_error, reason}
    end
  end

  defp fetch_map_id(%{"map_id" => mid}) when is_binary(mid) and mid != "" do
    {:ok, mid}
  end

  defp fetch_map_id(%{"slug" => slug}) when is_binary(slug) and slug != "" do
    case WandererApp.Api.Map.get_map_by_slug(slug) do
      {:ok, map} ->
        {:ok, map.id}

      {:error, _reason} ->
        {:error, "No map found for slug=#{slug}"}
    end
  end

  defp fetch_map_id(_), do: {:error, "Must provide either ?map_id=UUID or ?slug=SLUG"}

  defp require_param(params, key) do
    case params[key] do
      nil -> {:error, "Missing required param: #{key}"}
      "" -> {:error, "Param #{key} cannot be empty"}
      val -> {:ok, val}
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {num, ""} -> {:ok, num}
      _ -> {:error, "Invalid integer for param id=#{str}"}
    end
  end

  defp read_characters_by_ids(ids) when is_list(ids) do
    if ids == [] do
      {:ok, []}
    else
      query =
        Character
        |> filter(id in ^ids)

      Api.read(query)
    end
  end

  defp map_system_to_json(system) do
    Map.take(system, [
      :id,
      :map_id,
      :solar_system_id,
      :name,
      :custom_name,
      :temporary_name,
      :description,
      :tag,
      :labels,
      :locked,
      :visible,
      :status,
      :position_x,
      :position_y,
      :inserted_at,
      :updated_at
    ])
  end

  defp character_to_json(ch) do
    Map.take(ch, [
      :id,
      :eve_id,
      :name,
      :corporation_id,
      :corporation_name,
      :corporation_ticker,
      :alliance_id,
      :alliance_name,
      :alliance_ticker,
      :inserted_at,
      :updated_at
    ])
  end


  defp static_system_to_json(system) do
    system
    |> Map.take([
      :solar_system_id,
      :region_id,
      :constellation_id,
      :solar_system_name,
      :solar_system_name_lc,
      :constellation_name,
      :region_name,
      :system_class,
      :security,
      :type_description,
      :class_title,
      :is_shattered,
      :effect_name,
      :effect_power,
      :statics,
      :wandering,
      :triglavian_invasion_status,
      :sun_type_id
    ])
  end

end
