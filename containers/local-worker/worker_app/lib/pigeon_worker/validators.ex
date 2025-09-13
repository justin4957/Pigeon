defmodule PigeonWorker.GExpressionValidator do
  @moduledoc """
  Local worker implementation of G-expression validator.
  Mirrors the functionality of Pigeon.Validators.GExpressionValidator
  """

  def validate(work_string, _opts) do
    try do
      case Jason.decode(work_string) do
        {:ok, gexpr_data} ->
          validate_gexpression(gexpr_data)

        {:error, decode_error} ->
          {:error, %{type: :invalid_json, message: inspect(decode_error)}}
      end
    rescue
      error ->
        {:error, %{type: :validation_exception, message: inspect(error)}}
    end
  end

  defp validate_gexpression(gexpr) do
    case validate_structure(gexpr) do
      :ok ->
        {:ok, %{
          status: :valid,
          structure: :valid,
          worker_validation: true,
          validated_at: System.system_time(:second)
        }}

      {:error, reason} ->
        {:error, %{
          status: :invalid,
          structure: :invalid,
          reason: reason,
          validated_at: System.system_time(:second)
        }}
    end
  end

  defp validate_structure(gexpr) when is_map(gexpr) do
    case Map.get(gexpr, "g") do
      nil -> {:error, "Missing 'g' field"}
      "lit" -> validate_literal(gexpr)
      "ref" -> validate_reference(gexpr)
      "app" -> validate_application(gexpr)
      "lam" -> validate_lambda(gexpr)
      "vec" -> validate_vector(gexpr)
      "match" -> validate_match(gexpr)
      "fix" -> validate_fixpoint(gexpr)
      unknown -> {:error, "Unknown G-expression type: #{unknown}"}
    end
  end

  defp validate_structure(_), do: {:error, "G-expression must be a map"}

  defp validate_literal(gexpr) do
    if Map.has_key?(gexpr, "v") do
      :ok
    else
      {:error, "Literal missing 'v' field"}
    end
  end

  defp validate_reference(gexpr) do
    case Map.get(gexpr, "v") do
      v when is_binary(v) -> :ok
      _ -> {:error, "Reference 'v' must be a string"}
    end
  end

  defp validate_application(gexpr) do
    case Map.get(gexpr, "v") do
      %{"fn" => fn_expr, "args" => args_expr} ->
        with :ok <- validate_structure(fn_expr),
             :ok <- validate_structure(args_expr) do
          :ok
        end

      _ ->
        {:error, "Application must have 'fn' and 'args' fields"}
    end
  end

  defp validate_lambda(gexpr) do
    case Map.get(gexpr, "v") do
      %{"params" => params, "body" => body} when is_list(params) ->
        if Enum.all?(params, &is_binary/1) do
          validate_structure(body)
        else
          {:error, "Lambda parameters must be strings"}
        end

      _ ->
        {:error, "Lambda must have 'params' (list) and 'body' fields"}
    end
  end

  defp validate_vector(gexpr) do
    case Map.get(gexpr, "v") do
      items when is_list(items) ->
        items
        |> Enum.reduce_while(:ok, fn item, :ok ->
          case validate_structure(item) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)

      _ ->
        {:error, "Vector 'v' must be a list"}
    end
  end

  defp validate_match(gexpr) do
    case Map.get(gexpr, "v") do
      %{"expr" => expr, "branches" => branches} when is_list(branches) ->
        validate_structure(expr)

      _ ->
        {:error, "Match must have 'expr' and 'branches' (list) fields"}
    end
  end

  defp validate_fixpoint(gexpr) do
    case Map.get(gexpr, "v") do
      inner_expr ->
        validate_structure(inner_expr)
    end
  end
end

defmodule PigeonWorker.JsonValidator do
  @moduledoc """
  Simple JSON validator for testing.
  """

  def validate(work_string, _opts) do
    case Jason.decode(work_string) do
      {:ok, data} ->
        {:ok, %{
          status: :valid,
          data_type: get_data_type(data),
          size: get_size(data),
          keys: get_keys(data),
          validated_at: System.system_time(:second)
        }}

      {:error, reason} ->
        {:error, %{
          status: :invalid,
          reason: "Invalid JSON: #{inspect(reason)}",
          validated_at: System.system_time(:second)
        }}
    end
  end

  defp get_data_type(data) when is_map(data), do: :object
  defp get_data_type(data) when is_list(data), do: :array
  defp get_data_type(data) when is_binary(data), do: :string
  defp get_data_type(data) when is_number(data), do: :number
  defp get_data_type(data) when is_boolean(data), do: :boolean
  defp get_data_type(nil), do: :null
  defp get_data_type(_), do: :unknown

  defp get_size(data) when is_map(data), do: map_size(data)
  defp get_size(data) when is_list(data), do: length(data)
  defp get_size(data) when is_binary(data), do: String.length(data)
  defp get_size(_), do: 1

  defp get_keys(data) when is_map(data), do: Map.keys(data)
  defp get_keys(_), do: []
end

defmodule PigeonWorker.DefaultValidator do
  @moduledoc """
  Default validator that accepts any work.
  """

  def validate(work_string, _opts) do
    {:ok, %{
      status: :valid,
      input_length: String.length(work_string),
      input_type: "string",
      validated_at: System.system_time(:second),
      worker_note: "Processed by default validator"
    }}
  end
end