defmodule AppWeb.DashboardUtilsTest do
  use ExUnit.Case, async: true
  import AppWeb.DashboardUtils

  describe "format_money/1" do
    test "formats number as Brazilian currency" do
      assert format_money(1234.56) == "R$\u00A01.234,56"
      assert format_money(0) == "R$\u00A00,00"
      assert format_money(1_000_000.99) == "R$\u00A01.000.000,99"
    end

    test "handles string input" do
      assert format_money("1234.56") == "R$\u00A01.234,56"
      assert format_money("invalid") == "R$ 0,00"
    end

    test "handles invalid input" do
      assert format_money(nil) == "R$ 0,00"
      assert format_money([]) == "R$ 0,00"
    end
  end

  describe "format_percent/1" do
    test "formats number as percentage" do
      assert format_percent(12.34) == "12,34%"
      assert format_percent(0) == "0,00%"
      assert format_percent(100.5) == "100,50%"
    end

    test "handles string input" do
      assert format_percent("12.34") == "12,34%"
      assert format_percent("invalid") == "0,00%"
    end

    test "handles invalid input" do
      assert format_percent(nil) == "0,00%"
      assert format_percent([]) == "0,00%"
    end
  end

  describe "parse_percent_to_number/1" do
    test "parses percentage strings correctly" do
      assert parse_percent_to_number("12,34%") == 12.34
      assert parse_percent_to_number("12.34%") == 12.34
      assert parse_percent_to_number("100%") == 100.0
      assert parse_percent_to_number("0%") == 0.0
    end

    test "handles numbers" do
      assert parse_percent_to_number(12.34) == 12.34
      assert parse_percent_to_number(0) == 0.0
    end

    test "handles invalid input" do
      assert parse_percent_to_number("") == 0.0
      assert parse_percent_to_number("invalid") == 0.0
      assert parse_percent_to_number(nil) == 0.0
    end
  end

  describe "get_numeric_value/2" do
    test "extracts numeric values from map" do
      data = %{"sale" => 1234.56, "cost" => "789.01", "invalid" => "abc"}

      assert get_numeric_value(data, "sale") == 1234.56
      assert get_numeric_value(data, "cost") == 789.01
      assert get_numeric_value(data, "invalid") == 0.0
      assert get_numeric_value(data, "missing") == 0.0
    end

    test "handles invalid data" do
      assert get_numeric_value(nil, "key") == 0.0
      assert get_numeric_value("not_a_map", "key") == 0.0
    end
  end

  describe "calculate_margin/1" do
    test "calculates margin correctly" do
      data = %{"sale" => 1000, "discount" => 100}
      assert calculate_margin(data) == 90.0
    end

    test "handles zero sale" do
      data = %{"sale" => 0, "discount" => 100}
      assert calculate_margin(data) == 0.0
    end

    test "handles missing data" do
      assert calculate_margin(%{}) == 0.0
    end
  end

  describe "calculate_ticket/1" do
    test "calculates ticket average correctly" do
      data = %{"sale" => 1000, "nfs" => 10}
      assert calculate_ticket(data) == 100.0
    end

    test "handles zero nfs" do
      data = %{"sale" => 1000, "nfs" => 0}
      assert calculate_ticket(data) == 0.0
    end

    test "handles missing data" do
      assert calculate_ticket(%{}) == 0.0
    end
  end
end
