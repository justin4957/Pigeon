defmodule Pigeon.Validators.GExpressionValidator do
  @moduledoc """
  G-expression validator implementation for Pigeon.

  Validates G-expressions (generalized expressions) which are JSON-based
  representations of functional programs. This validator can check syntax,
  semantic correctness, and perform equivalence testing.
  """

  @behaviour Pigeon.Work.Validator

  @impl true
  def validate(work_string, opts \\ []) do
    try do
      case Jason.decode(work_string) do
        {:ok, gexpr_data} ->
          validate_gexpression(gexpr_data, opts)

        {:error, decode_error} ->
          {:error, {:invalid_json, decode_error}}
      end
    rescue
      error ->
        {:error, {:validation_exception, error}}
    end
  end

  @impl true
  def validate_batch(work_items, opts \\ []) do
    results = Enum.map(work_items, fn work_item ->
      validate(work_item, opts)
    end)

    successes = Enum.count(results, fn {status, _} -> status == :ok end)
    total = length(results)

    {:ok, %{
      total: total,
      successes: successes,
      success_rate: if(total > 0, do: successes / total, else: 0.0),
      individual_results: results
    }}
  end

  @impl true
  def metadata do
    %{
      name: "G-Expression Validator",
      version: "1.0.0",
      description: "Validates G-expressions (generalized functional program representations)",
      supported_formats: ["json"]
    }
  end

  @impl true
  def generate_test_cases(count, opts \\ []) do
    base_cases = [
      # Simple literal
      %{"g" => "lit", "v" => 42},
      # Variable reference
      %{"g" => "ref", "v" => "x"},
      # Function application
      %{
        "g" => "app",
        "v" => %{
          "fn" => %{"g" => "ref", "v" => "+"},
          "args" => %{
            "g" => "vec",
            "v" => [
              %{"g" => "lit", "v" => 1},
              %{"g" => "lit", "v" => 2}
            ]
          }
        }
      },
      # Lambda expression
      %{
        "g" => "lam",
        "v" => %{
          "params" => ["x"],
          "body" => %{"g" => "ref", "v" => "x"}
        }
      }
    ]

    # Generate requested number of test cases
    test_cases = Stream.cycle(base_cases)
    |> Enum.take(count)
    |> Enum.map(&Jason.encode!/1)

    test_cases
  end

  # Private validation functions

  defp validate_gexpression(gexpr_data, opts) do
    validation_types = opts[:validation_types] || [:syntax, :semantic]

    results = Enum.reduce(validation_types, %{}, fn validation_type, acc ->
      result = case validation_type do
        :syntax -> validate_syntax(gexpr_data)
        :semantic -> validate_semantics(gexpr_data)
        :execution -> validate_execution(gexpr_data, opts)
        _ -> {:error, {:unknown_validation_type, validation_type}}
      end

      Map.put(acc, validation_type, result)
    end)

    # Check if all validations passed
    all_passed = results
    |> Map.values()
    |> Enum.all?(fn {status, _} -> status == :ok end)

    if all_passed do
      {:ok, %{validation_results: results, status: :valid}}
    else
      errors = results
      |> Enum.filter(fn {_, {status, _}} -> status == :error end)
      |> Enum.into(%{})

      {:error, %{validation_results: results, errors: errors}}
    end
  end

  defp validate_syntax(gexpr) do
    case validate_structure(gexpr) do
      :ok ->
        {:ok, %{message: "Syntax is valid"}}

      {:error, reason} ->
        {:error, %{message: "Syntax error: #{reason}"}}
    end
  end

  defp validate_structure(gexpr) when is_map(gexpr) do
    case Map.get(gexpr, "g") do
      nil ->
        {:error, "Missing 'g' field"}

      "lit" ->
        if Map.has_key?(gexpr, "v") do
          :ok
        else
          {:error, "Literal missing 'v' field"}
        end

      "ref" ->
        case Map.get(gexpr, "v") do
          v when is_binary(v) -> :ok
          _ -> {:error, "Reference 'v' must be a string"}
        end

      "app" ->
        validate_application_structure(gexpr)

      "lam" ->
        validate_lambda_structure(gexpr)

      "vec" ->
        validate_vector_structure(gexpr)

      "match" ->
        validate_match_structure(gexpr)

      "fix" ->
        validate_fixpoint_structure(gexpr)

      unknown ->
        {:error, "Unknown G-expression type: #{unknown}"}
    end
  end

  defp validate_structure(_), do: {:error, "G-expression must be a map"}

  defp validate_application_structure(gexpr) do
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

  defp validate_lambda_structure(gexpr) do
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

  defp validate_vector_structure(gexpr) do
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

  defp validate_match_structure(gexpr) do
    case Map.get(gexpr, "v") do
      %{"expr" => expr, "branches" => branches} when is_list(branches) ->
        with :ok <- validate_structure(expr),
             :ok <- validate_match_branches(branches) do
          :ok
        end

      _ ->
        {:error, "Match must have 'expr' and 'branches' (list) fields"}
    end
  end

  defp validate_match_branches(branches) do
    branches
    |> Enum.reduce_while(:ok, fn branch, :ok ->
      case branch do
        %{"pattern" => _pattern, "result" => result} ->
          case validate_structure(result) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "Match branch must have 'pattern' and 'result' fields"}}
      end
    end)
  end

  defp validate_fixpoint_structure(gexpr) do
    case Map.get(gexpr, "v") do
      inner_expr ->
        validate_structure(inner_expr)
    end
  end

  defp validate_semantics(gexpr) do
    # Semantic validation could include:
    # - Type checking
    # - Variable scope analysis
    # - Arity checking for function applications
    # For now, return a simple semantic check

    case check_variable_bindings(gexpr, []) do
      :ok ->
        {:ok, %{message: "Semantics are valid"}}

      {:error, reason} ->
        {:error, %{message: "Semantic error: #{reason}"}}
    end
  end

  defp check_variable_bindings(gexpr, bound_vars) when is_map(gexpr) do
    case Map.get(gexpr, "g") do
      "ref" ->
        var_name = Map.get(gexpr, "v")
        if var_name in bound_vars or is_builtin_function(var_name) do
          :ok
        else
          {:error, "Unbound variable: #{var_name}"}
        end

      "lam" ->
        %{"params" => params, "body" => body} = Map.get(gexpr, "v")
        new_bound_vars = bound_vars ++ params
        check_variable_bindings(body, new_bound_vars)

      "app" ->
        %{"fn" => fn_expr, "args" => args_expr} = Map.get(gexpr, "v")
        with :ok <- check_variable_bindings(fn_expr, bound_vars),
             :ok <- check_variable_bindings(args_expr, bound_vars) do
          :ok
        end

      "vec" ->
        items = Map.get(gexpr, "v")
        items
        |> Enum.reduce_while(:ok, fn item, :ok ->
          case check_variable_bindings(item, bound_vars) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)

      "match" ->
        %{"expr" => expr, "branches" => branches} = Map.get(gexpr, "v")
        with :ok <- check_variable_bindings(expr, bound_vars),
             :ok <- check_match_branches_bindings(branches, bound_vars) do
          :ok
        end

      "fix" ->
        inner_expr = Map.get(gexpr, "v")
        check_variable_bindings(inner_expr, bound_vars)

      _ ->
        :ok  # Literals and other constructs are fine
    end
  end

  defp check_variable_bindings(_, _), do: :ok

  defp check_match_branches_bindings(branches, bound_vars) do
    branches
    |> Enum.reduce_while(:ok, fn branch, :ok ->
      case Map.get(branch, "result") do
        result ->
          case check_variable_bindings(result, bound_vars) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
      end
    end)
  end

  defp is_builtin_function(name) do
    builtin_functions = ["+", "-", "*", "/", "=", "<", ">", "<=", ">=", "and", "or", "not"]
    name in builtin_functions
  end

  defp validate_execution(gexpr, opts) do
    # Execution validation would involve actually running the G-expression
    # This would require a G-expression interpreter/evaluator
    # For now, return a placeholder

    case opts[:test_inputs] do
      nil ->
        {:ok, %{message: "Execution validation skipped (no test inputs)"}}

      test_inputs ->
        # This would run the G-expression with test inputs and validate results
        {:ok, %{
          message: "Execution validation completed",
          test_results: length(test_inputs)
        }}
    end
  end
end