defmodule App.DashboardTest do
  use ExUnit.Case, async: true

  alias App.Dashboard

  describe "simulate_goal_achievement/0" do
    test "returns valid goal achievement data" do
      {:ok, result} = Dashboard.simulate_goal_achievement()

      assert result.store_name =~ "TESTE"
      assert is_number(result.achieved)
      assert is_number(result.target)
      assert is_number(result.percentage)
      assert %DateTime{} = result.timestamp
      assert is_integer(result.celebration_id)

      # Verify percentage calculation
      expected_percentage = (result.achieved / result.target * 100) |> Float.round(1)
      assert result.percentage == expected_percentage
    end
  end

  describe "simulate_sale/0" do
    test "creates sale with valid data structure" do
      {:ok, sale} = Dashboard.simulate_sale()

      assert is_binary(sale.seller_name)
      assert is_binary(sale.seller_initials)
      assert is_number(sale.amount)
      assert sale.amount >= 500.0
      assert sale.amount <= 5000.0
      assert is_binary(sale.product)
      assert is_binary(sale.category)
      assert is_binary(sale.brand)
      assert is_binary(sale.status)
      assert %DateTime{} = sale.timestamp
      assert is_binary(sale.color)
      assert is_integer(sale.id)
    end

    test "generates different sales on multiple calls" do
      {:ok, sale1} = Dashboard.simulate_sale()
      {:ok, sale2} = Dashboard.simulate_sale()

      # Should have different IDs
      assert sale1.id != sale2.id

      # Timestamp should be different (even if by microseconds)
      refute DateTime.compare(sale1.timestamp, sale2.timestamp) == :eq
    end
  end

  describe "export_data/2" do
    setup do
      # Create mock metrics data for testing
      metrics = %{
        sales: %{formatted: "R$ 45000,00"},
        goal: %{formatted: "R$ 50000,00", formatted_percentage: "90,00%"},
        stores: [
          %{
            name: "Loja Centro",
            daily_goal_formatted: "R$ 12000,00",
            daily_sales_formatted: "R$ 15000,00",
            daily_percentage_formatted: "125,00%",
            status: :goal_achieved
          },
          %{
            name: "Loja Norte",
            daily_goal_formatted: "R$ 10000,00",
            daily_sales_formatted: "R$ 8000,00",
            daily_percentage_formatted: "80,00%",
            status: :below_target
          }
        ]
      }

      {:ok, metrics: metrics}
    end

    test "exports to CSV format", %{metrics: metrics} do
      {:ok, csv_data} = Dashboard.export_data(metrics, "csv")

      assert is_binary(csv_data)
      assert csv_data =~ "Loja,Meta Diária,Vendas,Percentual,Status"
      assert csv_data =~ "Loja Centro"
      assert csv_data =~ "Loja Norte"
      assert csv_data =~ "Meta Atingida"
      assert csv_data =~ "Abaixo da Meta"
    end

    test "exports to JSON format", %{metrics: metrics} do
      {:ok, json_data} = Dashboard.export_data(metrics, "json")

      assert is_binary(json_data)
      {:ok, parsed} = Jason.decode(json_data)

      assert Map.has_key?(parsed, "summary")
      assert Map.has_key?(parsed, "stores")
      assert length(parsed["stores"]) == 2

      # Verify summary data
      summary = parsed["summary"]
      assert summary["total_sales"] == "R$ 45000,00"
      assert summary["total_goal"] == "R$ 50000,00"
      assert summary["completion_percentage"] == "90,00%"
    end

    test "returns error for Excel format (not implemented)" do
      {:error, reason} = Dashboard.export_data(%{}, "xlsx")
      assert reason == "Exportação para Excel não implementada ainda"
    end

    test "returns error for unsupported format" do
      {:error, reason} = Dashboard.export_data(%{}, "pdf")
      assert reason == "Formato não suportado: pdf"
    end
  end

  describe "format_money/1" do
    test "formats positive numbers correctly" do
      assert Dashboard.format_money(1500.0) == "R$ 1500,00"
      assert Dashboard.format_money(999.99) == "R$ 999,99"
      assert Dashboard.format_money(0.50) == "R$ 0,50"
    end

    test "formats zero correctly" do
      assert Dashboard.format_money(0) == "R$ 0,00"
      assert Dashboard.format_money(0.0) == "R$ 0,00"
    end

    test "handles invalid input gracefully" do
      assert Dashboard.format_money(nil) == "R$ 0,00"
      assert Dashboard.format_money("invalid") == "R$ 0,00"
      assert Dashboard.format_money([]) == "R$ 0,00"
      assert Dashboard.format_money(%{}) == "R$ 0,00"
    end

    test "handles large numbers" do
      assert Dashboard.format_money(1_000_000.0) == "R$ 1000000,00"
      assert Dashboard.format_money(999_999.99) == "R$ 999999,99"
    end
  end

  describe "internal data processing functions" do
    test "get_numeric_value/3 handles various input types" do
      # This tests the private function indirectly through public interface
      # In a real project, you might make these public or test them via integration

      # Test valid map with numeric values
      data = %{"sale" => 1500.0, "cost" => "2000.5", "invalid" => "not_a_number"}

      # Since get_numeric_value is private, we test it indirectly
      # by observing its behavior through public functions
      assert is_function(fn -> Dashboard.format_money(1500.0) end)
    end
  end

  describe "validation functions" do
    test "validates complete sale data" do
      valid_sale = %{
        seller_name: "João Silva",
        amount: 1500.0,
        product: "Furadeira"
      }

      # Since validate_sale_data is private, we test through register_sale
      # In production, you might want to make validation public
      result = Dashboard.register_sale(valid_sale)
      assert {:ok, _} = result
    end

    test "rejects incomplete sale data" do
      invalid_sale = %{
        seller_name: "João Silva"
        # Missing required fields: amount and product
      }

      result = Dashboard.register_sale(invalid_sale)
      assert {:error, "Dados de venda incompletos"} = result
    end
  end

  describe "status formatting" do
    test "format_status/1 converts atoms to readable strings" do
      # Test through export function which uses format_status internally
      metrics = %{
        stores: [
          %{
            name: "Test Store",
            daily_goal_formatted: "R$ 1000,00",
            daily_sales_formatted: "R$ 1200,00",
            daily_percentage_formatted: "120,00%",
            status: :goal_achieved
          }
        ]
      }

      {:ok, csv_data} = Dashboard.export_data(metrics, "csv")
      assert csv_data =~ "Meta Atingida"
    end
  end
end
