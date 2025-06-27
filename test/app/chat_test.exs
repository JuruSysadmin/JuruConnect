defmodule App.ChatTest do
  use App.DataCase, async: true

  alias App.Chat
  alias App.Minio

  @valid_attrs %{
    order_id: "123456",
    sender_id: "user1",
    text: "Mensagem com imagem"
  }

  test "envia mensagem com upload de imagem e salva image_url" do
    # Simule um arquivo temporário
    File.write!("/tmp/teste.jpg", "fake image content")
    filename = "user1_test_image.jpg"

    # Simule upload para o MinIO
    {:ok, image_url} = Minio.upload_file("/tmp/teste.jpg", filename)

    # Envie a mensagem com image_url
    {:ok, msg} =
      Chat.send_message(
        @valid_attrs.order_id,
        @valid_attrs.sender_id,
        @valid_attrs.text,
        image_url
      )

    assert msg.image_url == image_url
    assert String.contains?(msg.image_url, filename)
  end
end
