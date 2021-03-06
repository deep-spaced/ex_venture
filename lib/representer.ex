defmodule Representer do
  @moduledoc """
  Implementation of the Representer pattern for the API
  """

  defguard known_extension?(extension) when extension in [
    "json",
    "collection",
    "hal",
    "mason",
    "siren"
  ]

  defmodule Collection do
    @moduledoc """
    Struct for a collection of `Representer.Item`s

    Contains the list of `:items`, `:pagination`, and a list of `:links`
    """

    defstruct [:href, :name, :items, :pagination, links: []]
  end

  defmodule Item do
    @moduledoc """
    Struct for an item that can be rendered in various formats

    Consists of an `:item` that contains a map of properties and a list
    of `:links` that may be associated with the item.
    """

    defstruct [:rel, :href, :item, :type, embedded: [], links: []]
  end

  defmodule Link do
    @moduledoc """
    Struct for a hypermedia link
    """

    defstruct [:rel, :href, :title, :template]
  end

  defmodule Pagination do
    @moduledoc """
    Pagination struct and link generators
    """

    defstruct [:base_url, :current_page, :total_pages, :total_count]

    @doc """
    Maybe add pagination links to the link list

    If pagination is nil, skip this
    """
    def maybe_paginate(links, nil), do: links

    def maybe_paginate(links, pagination) do
      cond do
        pagination.total_pages == 1 ->
          links

        pagination.current_page == 1 ->
          [next_link(pagination) | links]

        pagination.current_page == pagination.total_pages ->
          [prev_link(pagination) | links]

        true ->
          [next_link(pagination) | [prev_link(pagination) | links]]
      end
    end

    defp next_link(pagination) do
      %Representer.Link{rel: "next", href: page_path(pagination.base_url, pagination.current_page + 1)}
    end

    defp prev_link(pagination) do
      %Representer.Link{rel: "prev", href: page_path(pagination.base_url, pagination.current_page - 1)}
    end

    defp page_path(path, page) do
      uri = URI.parse(path)

      query =
        uri.query
        |> decode_query()
        |> Map.put(:page, page)
        |> URI.encode_query()

      %{uri | query: query}
      |> URI.to_string()
    end

    defp decode_query(nil), do: %{}

    defp decode_query(query) do
      URI.decode_query(query)
    end
  end

  @doc """
  Transform the internal representation based on the extension
  """
  def transform(struct, extension) do
    case extension do
      "collection" ->
        Representer.CollectionJSON.transform(struct)

      "hal" ->
        Representer.HAL.transform(struct)

      "siren" ->
        Representer.Siren.transform(struct)

      "mason" ->
        Representer.Mason.transform(struct)

      "json" ->
        Representer.JSON.transform(struct)
    end
  end

  defmodule Adapter do
    @moduledoc """
    Behaviour for representations to implement
    """

    @type json :: map()

    @callback transform(collection :: %Representer.Collection{}) :: json()

    @callback transform(item :: %Representer.Item{}) :: json()
  end

  defmodule JSON do
    @moduledoc """
    Adapter for plain JSON

    Renders the representation almost directly
    """

    @behaviour Representer.Adapter

    @impl true
    def transform(collection = %Representer.Collection{}) do
      %{}
      |> maybe_put("items", render_collection(collection))
      |> maybe_put("links", transform_links(collection.links))
    end

    def transform(item = %Representer.Item{}) do
      item.item
      |> maybe_put("links", transform_links(item.links))
    end

    defp maybe_put(map, _key, nil), do: map

    defp maybe_put(map, key, value) do
      Map.put(map, key, value)
    end

    defp render_collection(collection) do
      case collection.items do
        nil ->
          nil

        [] ->
          nil

        items ->
          Enum.map(items, &transform/1)
      end
    end

    defp transform_links(links) do
      Enum.map(links, fn link ->
        %{"rel" => link.rel, "href" => link.href}
      end)
    end
  end

  defmodule CollectionJSON do
    @moduledoc """
    Adapter for collection+json
    """

    @behaviour Representer.Adapter

    @impl true
    def transform(collection = %Representer.Collection{}) do
      collection =
        %{"version" => "1.0"}
        |> maybe_put("items", render_collection(collection))
        |> maybe_put("links", render_links(collection))
        |> maybe_put("href", collection.href)

      %{"collection" => collection}
    end

    def transform(item = %Representer.Item{}) do
      %{
        "version" => "1.0",
        "items" => Enum.map([item], &render_item/1)
      }
    end

    defp render_collection(collection) do
      case collection.items do
        nil ->
          nil

        [] ->
          nil

        items ->
          Enum.map(items, &render_item/1)
      end
    end

    defp maybe_put(map, _key, nil), do: map

    defp maybe_put(map, key, value) do
      Map.put(map, key, value)
    end

    defp render_links(collection) do
      collection.links
      |> Representer.Pagination.maybe_paginate(collection.pagination)
      |> transform_links()
    end

    defp render_item(item) do
      %{
        "href" => item.href,
        "data" => render_data(item.item),
        "links" => transform_links(item.links),
      }
    end

    defp render_data(properties) do
      Enum.map(properties, fn {key, value} ->
        %{"name" => key, "value" => value}
      end)
    end

    defp transform_links(links) do
      links
      |> Enum.reject(&(&1.rel == "self"))
      |> Enum.map(fn link ->
        %{
          "rel" => link.rel,
          "href" => link.href,
        }
      end)
    end
  end

  defmodule HAL do
    @moduledoc """
    The HAL JSON hypermedia format

    http://stateless.co/hal_specification.html
    """

    @behaviour Representer.Adapter

    @impl true
    def transform(collection = %Representer.Collection{}) do
      %{}
      |> maybe_put("_links", render_links(collection))
      |> maybe_put("_embedded", render_collection(collection))
    end

    def transform(item = %Representer.Item{}) do
      item.item
      |> Map.put("_links", transform_links(item.links))
      |> Map.put("_embedded", render_embedded(item.embedded))
    end

    defp render_embedded(embedded) do
      Enum.reduce(embedded, %{}, fn {name, list}, embedded ->
        Map.put(embedded, name, Enum.map(list, &transform/1))
      end)
    end

    defp render_collection(collection) do
      case collection.items do
        nil ->
          nil

        [] ->
          nil

        items ->
          %{collection.name => Enum.map(items, &transform/1)}
      end
    end

    defp render_links(collection) do
      collection.links
      |> Representer.Pagination.maybe_paginate(collection.pagination)
      |> transform_links()
    end

    defp maybe_put(map, _key, nil), do: map

    defp maybe_put(map, key, value) do
      Map.put(map, key, value)
    end

    defp transform_links(links) do
      Enum.reduce(links, %{}, fn link, links ->
        json =
          %{"href" => link.href}
          |> maybe_put(:name, link.title)
          |> maybe_put(:template, link.template)

        case Map.get(links, link.rel) do
          nil ->
            Map.put(links, link.rel, json)

          existing_links ->
            Map.put(links, link.rel, [json | List.wrap(existing_links)])
        end
      end)
    end
  end

  defmodule Siren do
    @moduledoc """
    The Siren hypermedia format

    https://github.com/kevinswiber/siren
    """

    @behaviour Representer.Adapter

    @impl true
    def transform(collection = %Representer.Collection{}) do
      %{}
      |> maybe_put("title", collection.name)
      |> maybe_put("links", render_links(collection))
      |> maybe_put("entities", render_collection(collection))
    end

    def transform(item = %Representer.Item{}) do
      %{}
      |> maybe_put("rel", item.rel)
      |> maybe_put("properties", item.item)
      |> maybe_put("links", transform_links(item.links))
      |> maybe_put("entities", render_embedded(item.embedded))
    end

    defp maybe_put(map, _key, nil), do: map

    defp maybe_put(map, key, value) do
      Map.put(map, key, value)
    end

    defp render_collection(collection) do
      case collection.items do
        nil ->
          nil

        [] ->
          nil

        items ->
          Enum.map(items, &transform/1)
      end
    end

    defp render_embedded([]), do: nil

    defp render_embedded(embedded) do
      Enum.reduce(embedded, [], fn {_name, list}, embedded ->
        Enum.reduce(list, embedded, fn item, embedded ->
          [transform(item) | embedded]
        end)
      end)
    end

    defp render_links(collection) do
      collection.links
      |> Representer.Pagination.maybe_paginate(collection.pagination)
      |> transform_links()
    end

    defp transform_links(links) do
      Enum.map(links, fn link ->
        %{"rel" => [link.rel], "href" => link.href}
      end)
    end
  end

  defmodule Mason do
    @moduledoc """
    The Siren hypermedia format

    https://github.com/JornWildt/Mason
    """

    @behaviour Representer.Adapter

    @impl true
    def transform(collection = %Representer.Collection{}) do
      %{"name" => collection.name}
      |> maybe_put("entities", render_collection(collection))
      |> maybe_put("@controls", render_links(collection))
    end

    def transform(item = %Representer.Item{}) do
      Map.put(item.item, "@controls", transform_links(item.links))
    end

    defp maybe_put(map, _key, nil), do: map

    defp maybe_put(map, key, value) do
      Map.put(map, key, value)
    end

    defp render_collection(collection) do
      case collection.items do
        nil ->
          nil

        [] ->
          nil

        items ->
          Enum.map(items, &transform/1)
      end
    end

    defp render_links(collection) do
      collection.links
      |> Enum.filter(fn link -> link.rel != "curies" end)
      |> Representer.Pagination.maybe_paginate(collection.pagination)
      |> transform_links()
    end

    defp transform_links(links) do
      links
        |> Enum.filter(fn link -> link.rel != "curies" end)
        |> Enum.reduce(%{}, fn link, links ->
          json =
            %{"href" => link.href}
            |> maybe_put(:title, link.title)

          case Map.get(links, link.rel) do
            nil ->
              Map.put(links, link.rel, json)

            existing_links ->
              Map.put(links, link.rel, [json | List.wrap(existing_links)])
          end
        end)
    end
  end
end
