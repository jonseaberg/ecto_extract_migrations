defmodule EctoExtractMigrations.Parsers.AlterSequence do
  import NimbleParsec

  alias EctoExtractMigrations.Parsers.Common

  # https://www.postgresql.org/docs/current/sql-altersequence.html

  # ALTER SEQUENCE [ IF EXISTS ] name
  #   [ AS data_type ]
  #   [ INCREMENT [ BY ] increment ]
  #   [ MINVALUE minvalue | NO MINVALUE ] [ MAXVALUE maxvalue | NO MAXVALUE ]
  #   [ START [ WITH ] start ]
  #   [ RESTART [ [ WITH ] restart ] ]
  #   [ CACHE cache ] [ [ NO ] CYCLE ]
  #   [ OWNED BY { table_name.column_name | NONE } ]
  # ALTER SEQUENCE [ IF EXISTS ] name OWNER TO { new_owner | CURRENT_USER | SESSION_USER }
  # ALTER SEQUENCE [ IF EXISTS ] name RENAME TO new_name
  # ALTER SEQUENCE [ IF EXISTS ] name SET SCHEMA new_schema

  whitespace = Common.whitespace()
  name = Common.name()

  schema_name = name
  bare_sequence_name = name |> unwrap_and_tag(:sequence)
  schema_qualified_sequence_name =
    schema_name |> ignore(ascii_char([?.])) |> concat(name) |> tag(:sequence)

  sequence_name = choice([schema_qualified_sequence_name, bare_sequence_name])

  bare_table_name = name |> unwrap_and_tag(:table)
  schema_qualified_table_name =
    schema_name |> ignore(ascii_char([?.])) |> concat(name) |> tag(:table)

  table_name = choice([schema_qualified_table_name, bare_table_name])

  column_name =
    name
    |> unwrap_and_tag(:column)

  table_column =
    table_name
    |> ignore(ascii_char([?.]))
    |> concat(column_name)

  if_exists =
    ignore(whitespace)
    |> string("IF EXISTS")

  owned_by =
    ignore(whitespace)
    |> ignore(string("OWNED BY"))
    |> ignore(whitespace)
    |> choice([table_column, string("NONE")])
    |> tag(:owned_by)

  alter_sequence =
    ignore(optional(whitespace))
    |> ignore(string("ALTER SEQUENCE"))
    |> ignore(optional(if_exists))
    |> ignore(whitespace)
    |> concat(sequence_name)
    |> concat(owned_by)
    |> ignore(ascii_char([?;]))
    |> ignore(optional(whitespace))
    |> reduce({Enum, :into, [%{}]})

  match_alter_sequence =
    optional(whitespace)
    |> string("ALTER SEQUENCE")

  defparsec :parsec_parse, alter_sequence

  defparsec :parsec_match, match_alter_sequence

  def parse(sql) do
    case parsec_parse(sql) do
      {:ok, [value], _, _, _, _} -> {:ok, value}
      error -> error
    end
  end

  def match(sql) do
    case parse(sql) do
      {:ok, value} ->
        {:ok, value}
      _ ->
        case parsec_match(sql) do
          {:ok, _, _, _, _, _} -> :start
          error -> error
        end
    end
  end

  def tag, do: :alter_sequence
end
