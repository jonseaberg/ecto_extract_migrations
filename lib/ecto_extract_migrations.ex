defmodule EctoExtractMigrations do
  @moduledoc """
  The main entry point is lib/mix/tasks/ecto_extract_migrations.ex.
  This module mainly has common library functions.
  """

  @app :ecto_extract_migrations

  require EEx

  @template_execute_sql """
      execute(
      \"\"\"
      <%= Regex.replace(~r/^/m, sql, "  ") %>
      \"\"\")
  """

  @template_execute_sql_updown """
      execute(
      \"\"\"
      <%= Regex.replace(~r/^/m, up_sql, "  ") %>
      \"\"\",
      \"\"\"
      <%= Regex.replace(~r/^/m, down_sql, "  ") %>
      \"\"\"
      )
  """

  # defmodule ParseError do
  #   defexception message: "default message"
  # end

  @doc "Parse line from SQL file (Stream.transform function)"
  @spec parse({binary, integer}, nil | {module, binary}) :: {list, nil | {module, binary}}

  # First line of SQL statement
  def parse({line, line_num}, nil) do
    module_parse({line, line_num})
  end

  # In multi-line SQL statement
  def parse({line, line_num}, {module, state}) do
    # Mix.shell().info("#{line_num}> #{line} #{inspect state}")
    case module.parse(line, state) do
      {:ok, value} ->
        # Parsing succeeded
        sql = state.sql <> line
        {[%{module: module, type: module.type(), line_num: line_num, sql: sql, data: value}], nil}
      {:continue, new_state} ->
        # Keep reading lines
        # This assumes that we will ultimately succeed, probably overly optimistic.
        # The alternative is to stop when e.g. we hit a line ending with ";"
        {[], {module, new_state}}
      {:error, _reason} ->
        {[], nil}
    end
  end

  @spec module_parse({binary, integer}) :: {list, nil | {module, map}}
  def module_parse(value) do
    modules = [
      EctoExtractMigrations.Commands.Whitespace,
      EctoExtractMigrations.Commands.Comment,

      EctoExtractMigrations.Commands.CreateExtension,
      EctoExtractMigrations.Commands.CreateSchema,
      EctoExtractMigrations.Commands.CreateIndex,
      EctoExtractMigrations.Commands.CreateTrigger,
      EctoExtractMigrations.Commands.CreateFunction,

      EctoExtractMigrations.Commands.AlterTable,
      EctoExtractMigrations.Commands.AlterSequence,

      EctoExtractMigrations.Commands.CreateTable,
      EctoExtractMigrations.Commands.CreateSequence,
      EctoExtractMigrations.Commands.CreateType,
      EctoExtractMigrations.Commands.CreateView,
    ]
    module_parse(value, modules)
  end

  @spec module_parse({binary, integer}, list(module)) :: {list, nil | {module, map}}
  def module_parse({line, line_num}, []) do
    # No parser matched line
    IO.puts("UNKNOWN #{line_num}> #{String.trim_trailing(line)}")
    {[], nil}
  end
  def module_parse({line, line_num}, [module | rest]) do
    case module.match(line) do
      {:ok, value} ->
        # Parsing succeeded
        {[%{module: module, type: module.type(), line_num: line_num, sql: line, data: value}], nil}
      {:continue, state} ->
        # Matched multi-line statement, keep going
        {[], {module, state}}
      {:error, _reason} ->
        # Try next parser
        module_parse({line, line_num}, rest)
    end
  end

  EEx.function_from_string(:def, :eval_template_execute_sql, @template_execute_sql, [:sql])

  EEx.function_from_string(:def, :eval_template_execute_sql, @template_execute_sql_updown, [:up_sql, :down_sql])

  @doc "Expand template file to path under priv/templates"
  @spec template_path(Path.t()) :: Path.t()
  def template_path(file) do
    template_dir = Application.app_dir(@app, ["priv", "templates"])
    Path.join(template_dir, file)
  end

  @doc "Evaluate template file with bindings"
  @spec eval_template_file(Path.t(), Keyword.t()) :: {:ok, binary} | {:error, term}
  def eval_template_file(template_file, bindings \\ []) do
    path = template_path(template_file)
    {:ok, EEx.eval_file(path, bindings, trim: true)}
  rescue
    e ->
      {:error, {:template, e}}
  end

  @doc "Evaluate template file with bindings"
  @spec eval_template(Path.t(), Keyword.t()) :: {:ok, binary} | {:error, term}
  def eval_template(template_file, bindings \\ []) do
    {:ok, EEx.eval_file(template_file, bindings, trim: true)}
  rescue
    e ->
      {:error, {:template, e}}
  end

  @doc "Convert SQL name to Elixir module name"
  @spec sql_name_to_module(binary | list(binary)) :: binary
  def sql_name_to_module(name) when is_binary(name), do: Macro.camelize(name)
  def sql_name_to_module(["public", name]), do: Macro.camelize(name)
  def sql_name_to_module([schema, name]) do
    "#{Macro.camelize(schema)}.#{Macro.camelize(name)}"
  end

  @doc "Convert schema qualified name in list format to binary"
  @spec object_name(binary | list(binary)) :: binary
  def object_name(name) when is_binary(name), do: name
  def object_name(["public", name]), do: name
  def object_name([schema, name]), do: "#{schema}.#{name}"

  @doc "Convert NimbleParsec result tuple into simple ok/error tuple"
  @spec parsec_result(tuple) :: {:ok, term} | {:error, term}
  def parsec_result(result) do
    case result do
      {:ok, [acc], "", _, _line, _offset} ->
        {:ok, acc}

      {:ok, _, rest, _, _line, _offset} ->
        {:error, "could not parse: " <> rest}

      {:error, reason, _rest, _context, _line, _offset} ->
        {:error, reason}
    end
  end
end
