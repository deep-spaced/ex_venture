defmodule Data.Exit do
  @moduledoc """
  Exit Schema
  """

  use Data.Schema

  alias Data.Room

  @directions ["north", "east", "south", "west", "up", "down", "in", "out"]

  schema "exits" do
    field(:direction, :string)
    field(:has_door, :boolean, default: false)

    belongs_to(:start, Room)
    belongs_to(:finish, Room)

    timestamps()
  end

  @doc """
  Get a list of directions
  """
  @spec directions() :: [String.t()]
  def directions(), do: @directions

  def changeset(struct, params) do
    struct
    |> cast(params, [:direction, :has_door, :start_id, :finish_id])
    |> validate_required([:direction, :has_door])
    |> validate_inclusion(:direction, @directions)
    |> foreign_key_constraint(:start_id)
    |> foreign_key_constraint(:finish_id)
    |> unique_constraint(:direction, name: :exits_direction_start_id_finish_id_index)
  end

  @doc """
  Load all exits for a room

  Adds them to the room as `exits`
  """
  @spec load_exits(Room.t()) :: Room.t()
  def load_exits(room, opts \\ []) do
    query = where(__MODULE__, [e], e.start_id == ^room.id)
    query =
      case Keyword.get(opts, :preload) do
        true ->
          query |> preload([:start, :finish])

        _ ->
          query
      end

    %{room | exits: query |> Repo.all()}
  end

  @doc """
  Check if a string is a valid exit

      iex> Data.Exit.exit?("north")
      true

      iex> Data.Exit.exit?("outside")
      false
  """
  @spec exit?(String.t()) :: boolean()
  def exit?("north"), do: true
  def exit?("south"), do: true
  def exit?("east"), do: true
  def exit?("west"), do: true
  def exit?("in"), do: true
  def exit?("out"), do: true
  def exit?("up"), do: true
  def exit?("down"), do: true
  def exit?(_), do: false

  @doc """
  From a direction find the opposite direction's id

      iex> Data.Exit.opposite_id("north")
      :south_id
      iex> Data.Exit.opposite_id(:north)
      :south_id

      iex> Data.Exit.opposite_id("east")
      :west_id
      iex> Data.Exit.opposite_id(:east)
      :west_id

      iex> Data.Exit.opposite_id("south")
      :north_id
      iex> Data.Exit.opposite_id(:south)
      :north_id

      iex> Data.Exit.opposite_id("west")
      :east_id
      iex> Data.Exit.opposite_id(:west)
      :east_id

      iex> Data.Exit.opposite_id("up")
      :down_id
      iex> Data.Exit.opposite_id(:up)
      :down_id

      iex> Data.Exit.opposite_id("down")
      :up_id
      iex> Data.Exit.opposite_id(:down)
      :up_id

      iex> Data.Exit.opposite_id("in")
      :out_id
      iex> Data.Exit.opposite_id(:in)
      :out_id

      iex> Data.Exit.opposite_id("out")
      :in_id
      iex> Data.Exit.opposite_id(:out)
      :in_id
  """
  @spec opposite_id(String.t() | atom) :: atom
  def opposite_id("north"), do: :south_id
  def opposite_id("east"), do: :west_id
  def opposite_id("south"), do: :north_id
  def opposite_id("west"), do: :east_id
  def opposite_id("up"), do: :down_id
  def opposite_id("down"), do: :up_id
  def opposite_id("in"), do: :out_id
  def opposite_id("out"), do: :in_id
  def opposite_id(:north), do: :south_id
  def opposite_id(:east), do: :west_id
  def opposite_id(:south), do: :north_id
  def opposite_id(:west), do: :east_id
  def opposite_id(:up), do: :down_id
  def opposite_id(:down), do: :up_id
  def opposite_id(:in), do: :out_id
  def opposite_id(:out), do: :in_id

  @doc """
  From a direction find the opposite direction's id

      iex> Data.Exit.opposite("north")
      :south
      iex> Data.Exit.opposite(:north)
      :south

      iex> Data.Exit.opposite("east")
      :west
      iex> Data.Exit.opposite(:east)
      :west

      iex> Data.Exit.opposite("south")
      :north
      iex> Data.Exit.opposite(:south)
      :north

      iex> Data.Exit.opposite("west")
      :east
      iex> Data.Exit.opposite(:west)
      :east

      iex> Data.Exit.opposite("up")
      :down
      iex> Data.Exit.opposite(:up)
      :down

      iex> Data.Exit.opposite("down")
      :up
      iex> Data.Exit.opposite(:down)
      :up

      iex> Data.Exit.opposite("in")
      :out
      iex> Data.Exit.opposite(:in)
      :out

      iex> Data.Exit.opposite("out")
      :in
      iex> Data.Exit.opposite(:out)
      :in
  """
  @spec opposite(String.t() | atom) :: atom
  def opposite("north"), do: :south
  def opposite("east"), do: :west
  def opposite("south"), do: :north
  def opposite("west"), do: :east
  def opposite("up"), do: :down
  def opposite("down"), do: :up
  def opposite("in"), do: :out
  def opposite("out"), do: :in
  def opposite(:north), do: :south
  def opposite(:east), do: :west
  def opposite(:south), do: :north
  def opposite(:west), do: :east
  def opposite(:up), do: :down
  def opposite(:down), do: :up
  def opposite(:in), do: :out
  def opposite(:out), do: :in

  @doc """
  Get an exit in a direction
  """
  @spec exit_to(Room.t(), String.t() | atom) :: Exit.t() | nil
  def exit_to(room, direction) do
    Enum.find(room.exits, &(&1.direction == to_string(direction)))
  end
end
