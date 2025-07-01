defmodule App.Chat.MessageTest do
  @moduledoc """
  Testes para o changeset de mensagens do chat, com foco em validações
  de tipo "imagem" e processamento de image_url.

  Desenvolvido seguindo TDD com documentação completa em português.
  """

  use App.DataCase, async: true

  alias App.Chat.Message
  alias Ecto.Changeset

  @valid_attrs %{
    text: "Mensagem de teste",
    sender_id: "user123",
    sender_name: "João Silva",
    order_id: "ORDER-123456",
    tipo: "mensagem",
    status: "sent",
    image_url: nil,
    mentions: [],
    has_mentions: false,
    reply_to: nil,
    is_reply: false,
    audio_url: nil,
    audio_duration: nil,
    audio_mime_type: nil
  }

  describe "changeset/2 para mensagens com tipo 'imagem'" do
    test "cria changeset válido para mensagem com tipo 'imagem' e image_url" do
      attrs = %{
        @valid_attrs
        | tipo: "imagem",
          image_url: "https://minio.exemplo.com/chat-uploads/image_123.jpg"
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert Changeset.get_change(changeset, :tipo) == "imagem"
      assert Changeset.get_change(changeset, :image_url) == "https://minio.exemplo.com/chat-uploads/image_123.jpg"
    end

    test "aceita mensagem com tipo 'imagem' e image_url nula" do
      attrs = %{@valid_attrs | tipo: "imagem", image_url: nil}

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert Changeset.get_change(changeset, :tipo) == "imagem"
      assert Changeset.get_change(changeset, :image_url) == nil
    end

    test "aceita mensagem com tipo 'imagem' e image_url vazia" do
      attrs = %{@valid_attrs | tipo: "imagem", image_url: ""}

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert Changeset.get_change(changeset, :tipo) == "imagem"
    end

    test "aceita image_url com diferentes protocolos válidos" do
      valid_urls = [
        "https://minio.exemplo.com/uploads/image.jpg",
        "http://localhost:9000/chat/image.png",
        "https://s3.amazonaws.com/bucket/image.gif",
        "http://192.168.1.100:9000/uploads/photo.webp"
      ]

      for url <- valid_urls do
        attrs = %{@valid_attrs | tipo: "imagem", image_url: url}
        changeset = Message.changeset(%Message{}, attrs)

        assert changeset.valid?, "URL deveria ser válida: #{url}"
        assert Changeset.get_change(changeset, :image_url) == url
      end
    end

    test "preserva outros campos quando tipo é 'imagem'" do
      # Teste com texto que contém menções para que extract_mentions funcione
      attrs = %{
        @valid_attrs
        | tipo: "imagem",
          text: "Imagem com menções @usuario1 e @usuario2",
          image_url: "https://exemplo.com/image.jpg",
          reply_to: 456
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert Changeset.get_change(changeset, :tipo) == "imagem"
      # extract_mentions irá definir estas com base no texto
      assert Changeset.get_change(changeset, :mentions) == ["usuario1", "usuario2"]
      assert Changeset.get_change(changeset, :has_mentions) == true
      assert Changeset.get_change(changeset, :reply_to) == 456
      assert Changeset.get_change(changeset, :is_reply) == true
    end
  end

  describe "changeset/2 validações de tipo" do
    test "aceita todos os tipos válidos incluindo 'imagem'" do
      # Tipos simples sem validações adicionais
      tipos_simples = ["mensagem", "imagem", "sistema"]

      for tipo <- tipos_simples do
        attrs = %{@valid_attrs | tipo: tipo}
        changeset = Message.changeset(%Message{}, attrs)

        assert changeset.valid?, "Tipo deveria ser válido: #{tipo}"
        assert Changeset.get_change(changeset, :tipo) == tipo
      end

      # Tipo audio requer campos específicos
      attrs_audio = %{
        @valid_attrs
        | tipo: "audio",
          audio_url: "https://exemplo.com/audio.mp3",
          audio_duration: 120
      }
      changeset_audio = Message.changeset(%Message{}, attrs_audio)

      assert changeset_audio.valid?, "Tipo 'audio' deveria ser válido com campos obrigatórios"
      assert Changeset.get_change(changeset_audio, :tipo) == "audio"
    end

    test "rejeita tipos inválidos" do
      tipos_invalidos = ["video", "documento", "arquivo", "invalido"]

      for tipo <- tipos_invalidos do
        attrs = %{@valid_attrs | tipo: tipo}
        changeset = Message.changeset(%Message{}, attrs)

        refute changeset.valid?, "Tipo deveria ser inválido: #{tipo}"
        assert changeset.errors[:tipo] != nil
      end


    end
  end

  describe "changeset/2 processamento de image_url" do
    test "preserva image_url quando fornecida para qualquer tipo de mensagem" do
      image_url = "https://exemplo.com/uploads/foto.jpg"

      # Testa para diferentes tipos de mensagem (exceto audio que tem validações específicas)
      tipos = ["mensagem", "imagem", "sistema"]

      for tipo <- tipos do
        attrs = %{@valid_attrs | tipo: tipo, image_url: image_url}
        changeset = Message.changeset(%Message{}, attrs)

        assert changeset.valid?
        assert Changeset.get_change(changeset, :image_url) == image_url
      end

      # Teste específico para audio com campos obrigatórios
      attrs_audio = %{
        @valid_attrs
        | tipo: "audio",
          image_url: image_url,
          audio_url: "https://exemplo.com/audio.mp3",
          audio_duration: 120
      }
      changeset_audio = Message.changeset(%Message{}, attrs_audio)

      assert changeset_audio.valid?
      assert Changeset.get_change(changeset_audio, :image_url) == image_url
    end

    test "não valida formato de URL para image_url (validação delegada para upload)" do
      # URLs inválidas que deveriam ser aceitas pelo changeset
      # (validação de formato é responsabilidade do serviço de upload)
      urls_invalidas = [
        "url-invalida",
        "não-é-url",
        "ftp://exemplo.com/image.jpg",
        "file:///local/path/image.jpg"
      ]

      for url <- urls_invalidas do
        attrs = %{@valid_attrs | tipo: "imagem", image_url: url}
        changeset = Message.changeset(%Message{}, attrs)

        assert changeset.valid?, "Changeset deveria aceitar URL: #{url}"
        assert Changeset.get_change(changeset, :image_url) == url
      end
    end
  end

  describe "changeset/2 casos de erro" do
    test "rejeita mensagem sem campos obrigatórios" do
      changeset = Message.changeset(%Message{}, %{})

      refute changeset.valid?
      assert changeset.errors[:text] != nil
      assert changeset.errors[:sender_id] != nil
      assert changeset.errors[:sender_name] != nil
      assert changeset.errors[:order_id] != nil
    end

    test "rejeita texto muito longo" do
      texto_longo = String.duplicate("a", 5001)
      attrs = %{@valid_attrs | text: texto_longo}

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:text] != nil
    end

    test "rejeita texto vazio" do
      attrs = %{@valid_attrs | text: ""}

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:text] != nil
    end
  end

  describe "changeset/2 extração de menções" do
    test "extrai menções de mensagem com tipo 'imagem'" do
      attrs = %{
        @valid_attrs
        | tipo: "imagem",
          text: "Olha esta foto @joao e @maria!",
          image_url: "https://exemplo.com/foto.jpg"
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert Changeset.get_change(changeset, :mentions) == ["joao", "maria"]
      assert Changeset.get_change(changeset, :has_mentions) == true
    end

    test "não extrai menções quando texto não contém menções em mensagem com imagem" do
      attrs = %{
        @valid_attrs
        | tipo: "imagem",
          text: "Foto do evento de hoje",
          image_url: "https://exemplo.com/evento.jpg"
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      # Como o texto não tem menções, a função extract_mentions não adiciona o campo ao changeset
      # Então get_change retorna nil, mas o valor final será [] do default
      mentions = Changeset.get_change(changeset, :mentions) || []
      has_mentions = Changeset.get_change(changeset, :has_mentions) || false
      assert mentions == []
      assert has_mentions == false
    end
  end

  describe "changeset/2 integração com replies" do
    test "permite resposta com tipo 'imagem'" do
      attrs = %{
        @valid_attrs
        | tipo: "imagem",
          image_url: "https://exemplo.com/resposta.jpg",
          reply_to: 123,
          text: "Respondendo com uma imagem"
      }

      changeset = Message.changeset(%Message{}, attrs)

      assert changeset.valid?
      assert Changeset.get_change(changeset, :tipo) == "imagem"
      assert Changeset.get_change(changeset, :reply_to) == 123
      assert Changeset.get_change(changeset, :is_reply) == true
    end
  end

  describe "changeset/2 estrutura de erro" do
    test "erros contêm informações detalhadas para debugging" do
      attrs = %{tipo: "tipo_invalido", text: ""}

      changeset = Message.changeset(%Message{}, attrs)

      refute changeset.valid?

      # Verificar estrutura dos erros conforme documentação do Context7
      assert is_list(changeset.errors)
      assert length(changeset.errors) > 0

      # Cada erro deve ser uma tupla {campo, {mensagem, detalhes}}
      for {field, {message, details}} <- changeset.errors do
        assert is_atom(field)
        assert is_binary(message)
        assert is_list(details)
      end
    end
  end
end
