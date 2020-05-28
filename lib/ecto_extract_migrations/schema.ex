defmodule EctoExtractMigrations.Schema do

  alias EctoExtractMigrations.ParseError

  @app :ecto_extract_migrations

  def create_migration(data, bindings) do
    Mix.shell().info("#{data[:type]} #{data[:name]}")
    bindings = Keyword.merge(bindings, [
      name: data[:name],
      module_name: data[:name]
    ])

    template_dir = Application.app_dir(@app, ["priv", "templates"])
    template_path = Path.join(template_dir, "schema.eex")
    EctoExtractMigrations.eval_template(template_path, bindings)
  end

  @doc "Parse line of SQL"
  @spec parse_sql_line({String.t(), non_neg_integer}, {fun() | nil, list() | nil, list()}) :: {fun(), list(), list()}
  def parse_sql_line({line, index}, {_fun, _local, global}) do
    sql = String.trim(line)

    case Regex.named_captures(~r/\s*CREATE\s+SCHEMA\s+(?<name>\w+)\s*;$/i, sql) do
      nil ->
        raise ParseError, line: index, message: "Could not match CREATE SCHEMA line"
      data ->
        {nil, nil, [%{type: :schema, sql: sql, name: data["name"]} | global]}
    end
  end

end
