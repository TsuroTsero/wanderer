defmodule WandererApp.Repo.Migrations.AddUserUniqHash do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    create unique_index(:user_v1, [:hash], name: "user_v1_unique_hash_index")
  end

  def down do
    drop_if_exists unique_index(:user_v1, [:hash], name: "user_v1_unique_hash_index")
  end
end