defmodule Pigeon.Work.Validator do
  @moduledoc """
  Behavior for work validators in Pigeon.

  Work validators define how to process and validate arbitrary work strings
  sent to remote nodes. This abstraction allows Pigeon to be used for any
  distributed work processing scenario.

  ## Example Implementations
  - G-expression validation
  - Code compilation testing
  - Data transformation validation
  - Machine learning model inference
  - Text processing and analysis
  """

  @doc """
  Validates a work string and returns a result.

  ## Parameters
  - `work_string`: The raw work data as a string
  - `opts`: Optional configuration for the validator

  ## Returns
  - `{:ok, result}` - Success with validation result
  - `{:error, reason}` - Validation failure with reason

  ## Examples

      iex> defmodule ExampleValidator do
      ...>   @behaviour Pigeon.Work.Validator
      ...>   def validate("valid", _opts), do: {:ok, %{status: :valid}}
      ...>   def validate("invalid", _opts), do: {:error, %{message: "Invalid work"}}
      ...>   def validate_batch(items, opts), do: {:ok, Enum.map(items, &validate(&1, opts))}
      ...>   def metadata(), do: %{name: "Simple", version: "1.0.0", description: "Test", supported_formats: ["text"]}
      ...> end
      iex> ExampleValidator.validate("valid", [])
      {:ok, %{status: :valid}}

  """
  @callback validate(work_string :: String.t(), opts :: keyword()) ::
              {:ok, result :: any()} | {:error, reason :: any()}

  @doc """
  Processes work in batch mode.

  ## Parameters
  - `work_items`: List of work strings to process
  - `opts`: Optional configuration for batch processing

  ## Returns
  - `{:ok, results}` - Success with list of results
  - `{:error, reason}` - Batch processing failure
  """
  @callback validate_batch(work_items :: [String.t()], opts :: keyword()) ::
              {:ok, results :: [any()]} | {:error, reason :: any()}

  @doc """
  Returns metadata about the validator.

  ## Returns
  Map containing validator information:
  - `name`: Human readable validator name
  - `version`: Validator version
  - `description`: What this validator does
  - `supported_formats`: List of supported input formats
  """
  @callback metadata() :: %{
              name: String.t(),
              version: String.t(),
              description: String.t(),
              supported_formats: [String.t()]
            }

  @doc """
  Generates test cases for the validator.

  ## Parameters
  - `count`: Number of test cases to generate
  - `opts`: Optional configuration for test generation

  ## Returns
  List of test work strings
  """
  @callback generate_test_cases(count :: integer(), opts :: keyword()) :: [String.t()]

  @optional_callbacks generate_test_cases: 2

  @doc """
  Helper function to validate that a module implements the Validator behavior.

  ## Examples

      iex> defmodule SimpleValidator do
      ...>   @behaviour Pigeon.Work.Validator
      ...>   def validate(_work, _opts), do: {:ok, %{}}
      ...>   def validate_batch(_items, _opts), do: {:ok, []}
      ...>   def metadata(), do: %{name: "Test", version: "1.0.0", description: "Test", supported_formats: []}
      ...> end
      iex> Pigeon.Work.Validator.validate_implementation(SimpleValidator)
      {:ok, :valid}

  """
  def validate_implementation(module) do
    required_callbacks = [
      {:validate, 2},
      {:validate_batch, 2},
      {:metadata, 0}
    ]

    missing_callbacks =
      required_callbacks
      |> Enum.reject(fn {fun, arity} ->
        function_exported?(module, fun, arity)
      end)

    case missing_callbacks do
      [] ->
        {:ok, :valid}

      missing ->
        {:error, {:missing_callbacks, missing}}
    end
  end

  @doc """
  Loads and validates a validator module from string.
  """
  def load_validator(module_string) when is_binary(module_string) do
    try do
      module = String.to_existing_atom("Elixir.#{module_string}")
      load_validator(module)
    rescue
      ArgumentError ->
        {:error, {:invalid_module, module_string}}
    end
  end

  def load_validator(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        case validate_implementation(module) do
          {:ok, :valid} ->
            {:ok, module}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:module_load_error, reason}}
    end
  end
end