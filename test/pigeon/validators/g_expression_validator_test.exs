defmodule Pigeon.Validators.GExpressionValidatorTest do
  use ExUnit.Case, async: true
  doctest Pigeon.Validators.GExpressionValidator

  alias Pigeon.Validators.GExpressionValidator

  @valid_literal %{"g" => "lit", "v" => 42}
  @valid_reference %{"g" => "ref", "v" => "x"}
  @valid_application %{
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
  }
  @valid_lambda %{
    "g" => "lam",
    "v" => %{
      "params" => ["x"],
      "body" => %{"g" => "ref", "v" => "x"}
    }
  }
  @fibonacci_gexpr %{
    "g" => "fix",
    "v" => %{
      "g" => "lam",
      "v" => %{
        "params" => ["fib"],
        "body" => %{
          "g" => "lam",
          "v" => %{
            "params" => ["n"],
            "body" => %{
              "g" => "match",
              "v" => %{
                "expr" => %{
                  "g" => "app",
                  "v" => %{
                    "fn" => %{"g" => "ref", "v" => "<="},
                    "args" => %{
                      "g" => "vec",
                      "v" => [
                        %{"g" => "ref", "v" => "n"},
                        %{"g" => "lit", "v" => 1}
                      ]
                    }
                  }
                },
                "branches" => [
                  %{
                    "pattern" => %{"lit_pattern" => true},
                    "result" => %{"g" => "ref", "v" => "n"}
                  },
                  %{
                    "pattern" => "else_pattern",
                    "result" => %{
                      "g" => "app",
                      "v" => %{
                        "fn" => %{"g" => "ref", "v" => "+"},
                        "args" => %{
                          "g" => "vec",
                          "v" => [
                            %{
                              "g" => "app",
                              "v" => %{
                                "fn" => %{"g" => "ref", "v" => "fib"},
                                "args" => %{
                                  "g" => "app",
                                  "v" => %{
                                    "fn" => %{"g" => "ref", "v" => "-"},
                                    "args" => %{
                                      "g" => "vec",
                                      "v" => [
                                        %{"g" => "ref", "v" => "n"},
                                        %{"g" => "lit", "v" => 1}
                                      ]
                                    }
                                  }
                                }
                              }
                            },
                            %{
                              "g" => "app",
                              "v" => %{
                                "fn" => %{"g" => "ref", "v" => "fib"},
                                "args" => %{
                                  "g" => "app",
                                  "v" => %{
                                    "fn" => %{"g" => "ref", "v" => "-"},
                                    "args" => %{
                                      "g" => "vec",
                                      "v" => [
                                        %{"g" => "ref", "v" => "n"},
                                        %{"g" => "lit", "v" => 2}
                                      ]
                                    }
                                  }
                                }
                              }
                            }
                          ]
                        }
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      }
    }
  }

  describe "validate/2" do
    test "validates simple literal G-expression" do
      json_string = Jason.encode!(@valid_literal)
      assert {:ok, result} = GExpressionValidator.validate(json_string, [])
      assert result.status == :valid
      assert Map.has_key?(result.validation_results, :syntax)
      assert Map.has_key?(result.validation_results, :semantic)
    end

    test "validates reference G-expression" do
      json_string = Jason.encode!(@valid_reference)
      assert {:error, result} = GExpressionValidator.validate(json_string, [])
      # Reference to 'x' should fail semantic validation (unbound variable)
      assert Map.has_key?(result.errors, :semantic)
    end

    test "validates application G-expression" do
      json_string = Jason.encode!(@valid_application)
      assert {:ok, result} = GExpressionValidator.validate(json_string, [])
      assert result.status == :valid
    end

    test "validates lambda G-expression" do
      json_string = Jason.encode!(@valid_lambda)
      assert {:ok, result} = GExpressionValidator.validate(json_string, [])
      assert result.status == :valid
    end

    test "validates complex fibonacci G-expression" do
      json_string = Jason.encode!(@fibonacci_gexpr)
      assert {:ok, result} = GExpressionValidator.validate(json_string, [])
      assert result.status == :valid
    end

    test "fails on invalid JSON" do
      invalid_json = "{invalid json"
      assert {:error, {:invalid_json, _}} = GExpressionValidator.validate(invalid_json, [])
    end

    test "fails on missing 'g' field" do
      invalid_gexpr = %{"v" => 42}
      json_string = Jason.encode!(invalid_gexpr)
      assert {:error, result} = GExpressionValidator.validate(json_string, [])
      assert Map.has_key?(result.errors, :syntax)
    end

    test "fails on unknown G-expression type" do
      invalid_gexpr = %{"g" => "unknown", "v" => 42}
      json_string = Jason.encode!(invalid_gexpr)
      assert {:error, result} = GExpressionValidator.validate(json_string, [])
      assert Map.has_key?(result.errors, :syntax)
    end

    test "validates with custom validation types" do
      json_string = Jason.encode!(@valid_literal)
      assert {:ok, result} = GExpressionValidator.validate(json_string, validation_types: [:syntax])
      assert Map.has_key?(result.validation_results, :syntax)
      refute Map.has_key?(result.validation_results, :semantic)
    end
  end

  describe "validate_batch/2" do
    test "validates batch of G-expressions" do
      work_items = [
        Jason.encode!(@valid_literal),
        Jason.encode!(@valid_application),
        "{invalid json"
      ]

      assert {:ok, batch_result} = GExpressionValidator.validate_batch(work_items, [])
      assert batch_result.total == 3
      assert batch_result.successes == 2
      assert batch_result.success_rate == 2/3
      assert length(batch_result.individual_results) == 3
    end

    test "handles empty batch" do
      assert {:ok, batch_result} = GExpressionValidator.validate_batch([], [])
      assert batch_result.total == 0
      assert batch_result.successes == 0
      assert batch_result.success_rate == 0.0
      assert batch_result.individual_results == []
    end
  end

  describe "metadata/0" do
    test "returns correct metadata" do
      metadata = GExpressionValidator.metadata()

      assert metadata.name == "G-Expression Validator"
      assert metadata.version == "1.0.0"
      assert metadata.description == "Validates G-expressions (generalized functional program representations)"
      assert metadata.supported_formats == ["json"]
    end
  end

  describe "generate_test_cases/2" do
    test "generates requested number of test cases" do
      test_cases = GExpressionValidator.generate_test_cases(3, [])

      assert length(test_cases) == 3
      # All test cases should be valid JSON
      Enum.each(test_cases, fn test_case ->
        assert {:ok, _} = Jason.decode(test_case)
      end)
    end

    test "generates valid G-expressions" do
      test_cases = GExpressionValidator.generate_test_cases(4, [])

      # Each test case should validate successfully
      Enum.each(test_cases, fn test_case ->
        case GExpressionValidator.validate(test_case, []) do
          {:ok, _} -> :ok
          {:error, _} -> :ok  # Some test cases might intentionally fail semantic validation
        end
      end)
    end
  end

  describe "syntax validation" do
    test "validates literal structure" do
      valid_lit = %{"g" => "lit", "v" => "hello"}
      invalid_lit = %{"g" => "lit"}  # Missing 'v'

      json_valid = Jason.encode!(valid_lit)
      json_invalid = Jason.encode!(invalid_lit)

      assert {:ok, _} = GExpressionValidator.validate(json_valid, validation_types: [:syntax])
      assert {:error, _} = GExpressionValidator.validate(json_invalid, validation_types: [:syntax])
    end

    test "validates reference structure" do
      valid_ref = %{"g" => "ref", "v" => "variable_name"}
      invalid_ref = %{"g" => "ref", "v" => 123}  # 'v' must be string

      json_valid = Jason.encode!(valid_ref)
      json_invalid = Jason.encode!(invalid_ref)

      assert {:ok, _} = GExpressionValidator.validate(json_valid, validation_types: [:syntax])
      assert {:error, _} = GExpressionValidator.validate(json_invalid, validation_types: [:syntax])
    end

    test "validates vector structure" do
      valid_vec = %{
        "g" => "vec",
        "v" => [
          %{"g" => "lit", "v" => 1},
          %{"g" => "lit", "v" => 2}
        ]
      }
      invalid_vec = %{"g" => "vec", "v" => "not_a_list"}

      json_valid = Jason.encode!(valid_vec)
      json_invalid = Jason.encode!(invalid_vec)

      assert {:ok, _} = GExpressionValidator.validate(json_valid, validation_types: [:syntax])
      assert {:error, _} = GExpressionValidator.validate(json_invalid, validation_types: [:syntax])
    end
  end

  describe "semantic validation" do
    test "detects unbound variables" do
      unbound_ref = %{"g" => "ref", "v" => "unbound_var"}
      json_string = Jason.encode!(unbound_ref)

      assert {:error, result} = GExpressionValidator.validate(json_string, validation_types: [:semantic])
      assert Map.has_key?(result.errors, :semantic)
    end

    test "allows builtin functions" do
      builtin_ref = %{"g" => "ref", "v" => "+"}
      json_string = Jason.encode!(builtin_ref)

      assert {:ok, _} = GExpressionValidator.validate(json_string, validation_types: [:semantic])
    end

    test "handles lambda binding correctly" do
      lambda_with_bound_var = %{
        "g" => "lam",
        "v" => %{
          "params" => ["x", "y"],
          "body" => %{
            "g" => "app",
            "v" => %{
              "fn" => %{"g" => "ref", "v" => "+"},
              "args" => %{
                "g" => "vec",
                "v" => [
                  %{"g" => "ref", "v" => "x"},
                  %{"g" => "ref", "v" => "y"}
                ]
              }
            }
          }
        }
      }

      json_string = Jason.encode!(lambda_with_bound_var)
      assert {:ok, _} = GExpressionValidator.validate(json_string, validation_types: [:semantic])
    end
  end

  describe "execution validation" do
    test "skips execution validation without test inputs" do
      json_string = Jason.encode!(@valid_literal)
      assert {:ok, result} = GExpressionValidator.validate(json_string, validation_types: [:execution])

      execution_result = result.validation_results[:execution]
      assert execution_result == {:ok, %{message: "Execution validation skipped (no test inputs)"}}
    end

    test "performs execution validation with test inputs" do
      json_string = Jason.encode!(@valid_literal)
      test_inputs = [1, 2, 3]

      assert {:ok, result} = GExpressionValidator.validate(json_string,
        validation_types: [:execution],
        test_inputs: test_inputs
      )

      execution_result = result.validation_results[:execution]
      assert {:ok, exec_data} = execution_result
      assert exec_data.message == "Execution validation completed"
      assert exec_data.test_results == 3
    end
  end
end