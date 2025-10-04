defmodule AppWeb.ChatLive.PresenceManagerTest do
  use ExUnit.Case, async: true
  import Mox

  alias AppWeb.ChatLive.PresenceManager

  describe "track_user_presence/5" do
    test "tracks user presence successfully" do
      topic = "treaty:123"
      socket = %{id: "socket_123"}
      user_name = "João"
      authenticated_user = %{id: 1}
      treaty_id = "123"

      # Mock do Phoenix.Presence
      expect(AppWeb.PresenceMock, :track, fn _, ^topic, ^socket, _user_data ->
        {:ok, %{}}
      end)

      # Mock do Process.whereis para ActiveRooms
      expect(ProcessMock, :whereis, fn App.ActiveRooms -> :pid end)
      expect(App.ActiveRoomsMock, :join_room, fn ^treaty_id, 1, ^user_name -> :ok end)

      result = PresenceManager.track_user_presence(topic, socket, user_name, authenticated_user, treaty_id)

      assert result == :ok
    end

    test "handles tracking failure gracefully" do
      topic = "treaty:123"
      socket = %{id: "socket_123"}
      user_name = "João"
      authenticated_user = %{id: 1}
      treaty_id = "123"

      expect(AppWeb.PresenceMock, :track, fn _, ^topic, ^socket, _user_data ->
        {:error, :timeout}
      end)

      result = PresenceManager.track_user_presence(topic, socket, user_name, authenticated_user, treaty_id)

      assert result == :error
    end
  end

  describe "get_presences/1" do
    test "returns presences for valid topic" do
      topic = "treaty:123"
      expected_presences = %{
        "socket_1" => %{metas: [%{name: "João", user_id: 1}]},
        "socket_2" => %{metas: [%{name: "Maria", user_id: 2}]}
      }

      expect(AppWeb.PresenceMock, :list, fn ^topic -> expected_presences end)

      result = PresenceManager.get_presences(topic)

      assert result == expected_presences
    end

    test "returns empty map on error" do
      topic = "treaty:123"

      expect(AppWeb.PresenceMock, :list, fn ^topic -> raise "Connection error" end)

      result = PresenceManager.get_presences(topic)

      assert result == %{}
    end
  end

  describe "extract_online_users/1" do
    test "extracts unique user names from presences" do
      presences = %{
        "socket_1" => %{metas: [%{name: "João"}]},
        "socket_2" => %{metas: [%{name: "Maria"}]},
        "socket_3" => %{metas: [%{name: "João"}]}  # Duplicate
      }

      result = PresenceManager.extract_online_users(presences)

      assert result == ["João", "Maria"]
    end

    test "handles empty presences" do
      result = PresenceManager.extract_online_users(%{})

      assert result == []
    end

    test "handles invalid presences" do
      result = PresenceManager.extract_online_users(nil)

      assert result == []
    end
  end

  describe "is_user_online?/2" do
    test "returns true when user is online" do
      treaty_id = "123"
      user_id = 1
      presences = %{
        "socket_1" => %{metas: [%{user_id: 1, name: "João"}]},
        "socket_2" => %{metas: [%{user_id: 2, name: "Maria"}]}
      }

      expect(AppWeb.PresenceMock, :list, fn "treaty:123" -> presences end)

      result = PresenceManager.is_user_online?(treaty_id, user_id)

      assert result == true
    end

    test "returns false when user is offline" do
      treaty_id = "123"
      user_id = 3
      presences = %{
        "socket_1" => %{metas: [%{user_id: 1, name: "João"}]},
        "socket_2" => %{metas: [%{user_id: 2, name: "Maria"}]}
      }

      expect(AppWeb.PresenceMock, :list, fn "treaty:123" -> presences end)

      result = PresenceManager.is_user_online?(treaty_id, user_id)

      assert result == false
    end
  end

  describe "get_presence_info/1" do
    test "returns formatted presence information" do
      treaty_id = "123"
      presences = %{
        "socket_1" => %{metas: [%{name: "João", user_id: 1}]},
        "socket_2" => %{metas: [%{name: "Maria", user_id: 2}]}
      }

      expect(AppWeb.PresenceMock, :list, fn "treaty:123" -> presences end)

      result = PresenceManager.get_presence_info(treaty_id)

      assert result.presences == presences
      assert result.online_users == ["João", "Maria"]
      assert result.online_count == 2
      assert result.topic == "treaty:123"
    end
  end
end
