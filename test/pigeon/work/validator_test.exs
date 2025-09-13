defmodule Pigeon.Work.ValidatorTest do
  use ExUnit.Case, async: true
  doctest Pigeon.Work.Validator

  alias Pigeon.Work.Validator

  defmodule TestValidator do
    @behaviour Validator

    def validate("valid", _opts), do: {:ok, %{status: :valid}}
    def validate("invalid", _opts), do: {:error, %{message: "Invalid work"}}
    def validate(_, _opts), do: {:error, %{message: "Unknown work"}}

    def validate_batch(work_items, opts) do
      results = Enum.map(work_items, &validate(&1, opts))
      {:ok, results}
    end

    def metadata do
      %{
        name: "Test Validator",
        version: "1.0.0",
        description: "A validator for testing",
        supported_formats: ["text"]
      }
    end

    def generate_test_cases(count, _opts) do
      Enum.map(1..count, fn i ->
        if rem(i, 2) == 0, do: "valid", else: "invalid"
      end)
    end
  end

  defmodule IncompleteValidator do
    @behaviour Validator

    def validate(_work, _opts), do: {:ok, %{}}
    def metadata, do: %{name: "Incomplete", version: "1.0.0", description: "Test", supported_formats: []}
    # Missing validate_batch/2
  end

  describe "validate_implementation/1" do
    test "returns :ok for valid implementation" do
      assert {:ok, :valid} = Validator.validate_implementation(TestValidator)
    end

    test "returns error for incomplete implementation" do
      assert {:error, {:missing_callbacks, missing}} = Validator.validate_implementation(IncompleteValidator)
      assert {:validate_batch, 2} in missing
    end

    test "returns error for non-existent module" do
      assert {:error, {:missing_callbacks, _}} = Validator.validate_implementation(NonExistentModule)
    end
  end

  describe "load_validator/1 with string" do
    test "loads valid module from string" do
      module_string = "Pigeon.Work.ValidatorTest.TestValidator"
      assert {:ok, TestValidator} = Validator.load_validator(module_string)
    end

    test "returns error for invalid module string" do
      assert {:error, {:invalid_module, "NonExistent"}} = Validator.load_validator("NonExistent")
    end

    test "returns error for incomplete validator" do
      module_string = "Pigeon.Work.ValidatorTest.IncompleteValidator"
      assert {:error, {:missing_callbacks, _}} = Validator.load_validator(module_string)
    end
  end

  describe "load_validator/1 with atom" do
    test "loads valid module from atom" do
      assert {:ok, TestValidator} = Validator.load_validator(TestValidator)
    end

    test "returns error for non-existent module atom" do
      assert {:error, {:module_load_error, _}} = Validator.load_validator(NonExistentModule)
    end

    test "returns error for incomplete validator atom" do
      assert {:error, {:missing_callbacks, _}} = Validator.load_validator(IncompleteValidator)
    end
  end

  describe "validator behavior" do
    test "TestValidator validates correctly" do
      assert {:ok, %{status: :valid}} = TestValidator.validate("valid", [])
      assert {:error, %{message: "Invalid work"}} = TestValidator.validate("invalid", [])
      assert {:error, %{message: "Unknown work"}} = TestValidator.validate("unknown", [])
    end

    test "TestValidator batch validation works" do
      work_items = ["valid", "invalid", "unknown"]
      assert {:ok, batch_result} = TestValidator.validate_batch(work_items, [])

      assert length(batch_result) == 3
      assert [{:ok, %{status: :valid}}, {:error, %{message: "Invalid work"}}, {:error, %{message: "Unknown work"}}] = batch_result
    end

    test "TestValidator metadata is correct" do
      metadata = TestValidator.metadata()

      assert metadata.name == "Test Validator"
      assert metadata.version == "1.0.0"
      assert metadata.description == "A validator for testing"
      assert metadata.supported_formats == ["text"]
    end

    @tag :skip
    test "TestValidator generates test cases" do
      test_cases = TestValidator.generate_test_cases(4, [])

      assert length(test_cases) == 4
      assert test_cases == ["invalid", "valid", "invalid", "valid"]
    end
  end
end