defmodule Mix.Tasks.Ecto.Extract.Migrations do
  @moduledoc """
  Mix task to create Ecto migration files from database schema.

  ## Command line options

    * `--migrations-path` - target dir for migrations, defaults to "priv/repo/migrations".
    * `--sql-file` - target dir for migrations, defaults to "priv/repo/migrations".
    * `--repo` - Name of Ecto repo

  ## Usage

      mix ecto.extract.migrations --repo Foo
  """
  @shortdoc "Create Ecto migration files from db schema SQL file"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    opts = [
      strict: [
        migrations_path: :string,
        sql_file: :string,
        repo: :string,
        verbose: :boolean
      ]
    ]
    {overrides, _} = OptionParser.parse!(args, opts)

    repo = overrides[:repo] || "Repo"
    sql_file = overrides[:sql_file]

    migrations_path = get_migrations_path(overrides)
    :ok = File.mkdir_p(migrations_path)

    results =
      sql_file
      |> File.stream!()
      |> Stream.with_index()
      |> Stream.transform(nil, &parse/2)
      |> Stream.reject(&(&1.type in [:whitespace, :comment]))
      |> Enum.to_list()

    # for result <- results do
    #   Mix.shell().info("#{inspect result}")
    # end

    # TODO
    # CREATE TABLE
    #   Parse CONSTRAINTS with new expression parser
    #   Column options are not in order, use choice
    #     e.g. public.login_log
    #   Handle column constraints
    #
    # ALTER TABLE
    #   ALTER TABLE ONLY chat.assignment ALTER COLUMN id SET DEFAULT nextval
    #   ALTER TABLE ONLY chat.session ADD CONSTRAINT session_token_key UNIQUE (token);
    #   ALTER TABLE ONLY chat.assignment ADD CONSTRAINT assignment_care_taker_id_fkey FOREIGN KEY (user_id) REFERENCES chat."user"(id);
    #
    #   Merge with create table
    #
    # CREATE INDEX
    #   Consolidate statements for performance
    #
    # CREATE FUNCTION
    # CREATE TRIGGER

    index = 1

    bindings = [
      repo: repo,
    ]

    by_type = Enum.group_by(results, &(&1.type))
    Mix.shell().info("types: #{inspect Map.keys(by_type)}")

    object_types = [:create_extension, :create_schema, :create_type]
    index =
      for object_type <- object_types, reduce: index do
        acc ->
          objects = by_type[object_type]
          for {%{module: module, sql: sql, data: data, idx: line}, index} <- Enum.with_index(objects, acc) do
            Mix.shell().info("SQL #{object_type} #{line} \n#{sql}\n#{inspect data}")
            data = Map.put(data, :sql, sql)

            {:ok, migration} = module.migration(data, bindings)
            file_name = module.file_name(data, bindings)
            path = Path.join(migrations_path, Enum.join([to_prefix(index), file_name], "_"))
            write_migration_file(migration, path)
          end
          acc + length(objects)
      end

    # Create sequences
    statements = for %{data: data, sql: sql} <- by_type[:create_sequence] do
      [schema, name] = data.name
      EctoExtractMigrations.Commands.CreateSequence.migration_statement(sql, schema, name)
    end
    {:ok, migration} = EctoExtractMigrations.Commands.CreateSequence.migration_combine(statements, bindings)
    filename = Path.join(migrations_path, "#{to_prefix(index)}_sequences.exs")
    write_migration_file(migration, filename)
    index = index + 1

    # Collect ALTER TABLE statements
    at_objects = Enum.group_by(by_type[:alter_table], &alter_table_type/1)

    # Collect table primary_keys from ALTER TABLE statements
    primary_keys =
      for %{data: data} <- at_objects[:primary_key], into: %{} do
        {data.table, data.primary_key}
      end

    # Collect table defaults from ALTER TABLE statements
    column_defaults =
      for result <- at_objects[:default], reduce: %{} do
        acc ->
          %{table: table, column: column, default: default} = result.data
          value = acc[table] || %{}
          Map.put(acc, table, Map.put(value, column, default))
      end

    # Collect table foreegn key constraints from ALTER TABLE statements

    # foreign_keys =
    #   for result <- at_objects[:foreign_key], reduce: %{} do
    #     acc ->
    #       data = result.data
    #       column_reference = Reference.column_reference(data)
    #       Mix.shell().info("foreign_key> #{inspect result}\n#{inspect column_reference}")
    #       %{table: table, columns: columns} = data
    #       value = acc[table] || %{}
    #       column = List.first(columns)
    #       Map.put(acc, table, Map.put(value, column, data))
    #   end

    # Collect table constraints
    table_constraints = Enum.flat_map(results, &get_table_constraints/1)
    Mix.shell().info("table_constraints: #{inspect table_constraints}")


    object_type = :create_table
    objects = by_type[object_type]
    for {%{module: module, sql: sql, data: data, idx: line}, index} <- Enum.with_index(objects, index) do
      Mix.shell().info("SQL #{object_type} #{line} \n#{sql}\n#{inspect data}")
      data = Map.put(data, :sql, sql)

      if data.name == ["public", "schema_migrations"] do
        # schema_migrations is created by ecto.migrate itself
        Mix.shell().info("Skipping schema_migrations")
        :ok
      else
        data =
          data
          |> table_set_pk(primary_keys[data.name])
          |> table_set_default(column_defaults[data.name])

        {:ok, migration} = module.migration(data, bindings)
        file_name = module.file_name(data, bindings)
        path = Path.join(migrations_path, file_name)
        write_migration_file(migration, path)
      end
    end
    index = index + length(objects)


    # object_types = [:create_view, :create_trigger, :create_index]
    object_types = [:create_view, :create_index]
    index =
      for object_type <- object_types, reduce: index do
        acc ->
          objects = by_type[object_type]
          for {%{module: module, sql: sql, data: data, idx: line}, index} <- Enum.with_index(objects, acc) do
            Mix.shell().info("SQL #{object_type} #{line} \n#{sql}\n#{inspect data}")
            data = Map.put(data, :sql, sql)

            {:ok, migration} = module.migration(data, bindings)
            file_name = module.file_name(data, bindings)
            path = Path.join(migrations_path, file_name)
            write_migration_file(migration, path)
          end
          acc + length(objects)
      end

    # object_types = [:default, :foreign_key, :unique]
    #index =
    for object_type <- [:foreign_key, :unique], reduce: index do
        acc ->
          objects = at_objects[object_type]
          for {%{sql: sql, data: data, idx: line}, index} <- Enum.with_index(objects, acc) do
            Mix.shell().info("SQL #{object_type} #{line} \n#{sql}\n#{inspect data}")
            data = Map.put(data, :sql, sql)

            module = migration_module(object_type)
            {:ok, migration} = module.migration(data, bindings)
            file_name = module.file_name(to_prefix(index), data, bindings)
            path = Path.join(migrations_path, file_name)
            write_migration_file(migration, path)
          end
          acc + length(objects)
      end
  end

  @spec parse({binary, integer}, nil | {module, binary}) :: {list, nil | {module, binary}}
  def parse({line, idx}, nil) do
    modules = [
      EctoExtractMigrations.Commands.Whitespace,
      EctoExtractMigrations.Commands.Comment,

      EctoExtractMigrations.Commands.CreateExtension,
      EctoExtractMigrations.Commands.CreateSchema,
      EctoExtractMigrations.Commands.CreateIndex,
      EctoExtractMigrations.Commands.CreateTrigger,

      EctoExtractMigrations.Commands.AlterTable,
      EctoExtractMigrations.Commands.AlterSequence,

      EctoExtractMigrations.Commands.CreateTable,
      EctoExtractMigrations.Commands.CreateSequence,
      EctoExtractMigrations.Commands.CreateType,
      EctoExtractMigrations.Commands.CreateView,
    ]

    module_parse(modules, {line, idx})
  end
  def parse({line, idx}, {module, lines}) do
    lines = lines <> line
    case module.parse(lines) do
      {:ok, value} ->
        {[%{module: module, type: module.type(), idx: idx, sql: lines, data: value}], nil}
      _ ->
        # Mix.shell().info("#{idx}> :rest #{String.trim_trailing(line)}")
        {[], {module, lines}}
    end
  end

  def module_parse([], {line, idx}) do
    # No parser matched line
    Mix.shell().info("#{idx}> #{String.trim_trailing(line)}")
    {[], nil}
  end
  def module_parse([module | rest], {line, idx} = acc) do
    case module.match(line) do
      {:ok, value} ->
        # Line parsed
        {[%{module: module, type: module.type(), idx: idx, sql: line, data: value}], nil}
      :start ->
        # Matched first line of multiline statement
        # Mix.shell().info("#{idx}> :start #{String.trim_trailing(line)}")
        {[], {module, line}}
      _ ->
        # Try next parser
        module_parse(rest, acc)
    end
  end

  def migration_module(:create_extension), do: EctoExtractMigrations.Migrations.CreateExtension
  def migration_module(:create_index), do: EctoExtractMigrations.Migrations.CreateIndex
  def migration_module(:create_schema), do: EctoExtractMigrations.Migrations.CreateSchema
  def migration_module(:create_table), do: EctoExtractMigrations.Migrations.CreateTable
  def migration_module(:create_trigger), do: EctoExtractMigrations.Migrations.CreateTrigger
  def migration_module(:create_type), do: EctoExtractMigrations.Migrations.CreateType
  def migration_module(:create_view), do: EctoExtractMigrations.Migrations.CreateView
  def migration_module(:default), do: EctoExtractMigrations.Migrations.Default
  def migration_module(:foreign_key), do: EctoExtractMigrations.Migrations.ForeignKey
  def migration_module(:unique), do: EctoExtractMigrations.Migrations.Unique

  defp get_migrations_path(overrides) do
    repo = overrides[:repo] || "Repo"
    repo_dir = Macro.underscore(repo)
    default_migrations_path = Path.join(["priv", repo_dir, "migrations"])
    overrides[:migrations_path] || default_migrations_path
  end

  def write_migration_file(migration, filename) do
    Mix.shell().info(filename)
    Mix.shell().info(migration)
    :ok = File.write(filename, migration)
  end

  def get_sequence_statements(results) do
    for result <- results, result.type == :create_sequence do
      [schema, name] = result.data.name
      EctoExtractMigrations.Migrations.CreateSequence.create_migration_statement(result.sql, schema, name)
    end
  end

  # ALTER TABLE ADD CONSTRAINT PRIMARY KEY
  def alter_table_type(%{data: %{action: :add_table_constraint, type: :primary_key}}), do: :primary_key
  # ALTER TABLE ADD CONSTRAINT FOREIGN KEY
  def alter_table_type(%{data: %{action: :add_table_constraint, type: :foreign_key}}), do: :foreign_key
  # ALTER TABLE ALTER COLUMN id SET DEFAULT
  def alter_table_type(%{data: %{action: :set_default}}), do: :default
  # ALTER TABLE ADD CONSTRAINT UNIQUE
  def alter_table_type(%{data: %{action: :add_table_constraint, type: :unique}}), do: :unique

  # Set primary_key: true on column if it is part of table primary key
  def table_set_pk(data, nil), do: data
  def table_set_pk(data, pk) do
    Mix.shell().info("setting pk: #{inspect data.name} #{inspect pk}")
    columns = data[:columns]
    # Mix.shell().info("setting pk columns: #{inspect columns}")
    columns = Enum.map(columns, &(column_set_pk(&1, pk)))
    # Mix.shell().info("setting pk columns: #{inspect columns}")
    %{data | columns: columns}
  end

  def column_set_pk(column, pk) do
    if column.name in pk do
      Mix.shell().info("setting pk column: #{inspect column}")
      Map.put(column, :primary_key, true)
    else
      column
    end
  end


  # Set default on column based on alter table
  def table_set_default(data, nil), do: data
  def table_set_default(data, defaults) do
    Mix.shell().info("setting default: #{inspect data.name} #{inspect defaults}")
    columns = Enum.map(data[:columns], &(column_set_default(&1, defaults)))
    %{data | columns: columns}
  end

  def column_set_default(data, defaults) do
    case Map.fetch(defaults, data.name) do
      {:ok, default} ->
        Map.put(data, :default, default)
      :error ->
        data
    end
  end


  def get_table_constraints(%{type: :create_table, data: %{name: name, constraints: constraints}}) do
    [%{table: name, constraints: constraints}]
  end
  def get_table_constraints(_), do: []


  # Create unique prefix for files from index
  @spec to_prefix(integer) :: binary
  defp to_prefix(index) do
    to_string(:io_lib.format('~4..0b', [index]))
  end
end
