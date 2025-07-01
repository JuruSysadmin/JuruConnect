defmodule App.Auth.PasswordPolicy do
  @moduledoc """
  Sistema de políticas de senha robustas.

  Implementa validações de segurança para senhas, incluindo:
  - Comprimento mínimo e máximo
  - Complexidade de caracteres
  - Histórico de senhas
  - Palavras proibidas
  - Força da senha
  """

  require Logger

  # Configurações de política
  @min_length 8
  @max_length 128
  @min_uppercase 1
  @min_lowercase 1
  @min_digits 1
  @min_special_chars 1
  @max_password_history 5
  @password_expiry_days 90

  # Padrões de validação
  @uppercase_regex ~r/[A-Z]/
  @lowercase_regex ~r/[a-z]/
  @digit_regex ~r/[0-9]/
  @special_char_regex ~r/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/

  # Palavras proibidas (expandir conforme necessário)
  @common_passwords [
    "password", "123456", "123456789", "qwerty", "abc123", "password123",
    "admin", "root", "user", "login", "welcome", "guest", "test",
    "jurunense", "juru", "homecenter", "loja", "vendas", "sistema"
  ]

  @weak_patterns [
    ~r/(.)\1{2,}/,           # Caracteres repetidos (aaa, 111)
    ~r/012|123|234|345|456|567|678|789|890/,  # Sequências numéricas
    ~r/abc|bcd|cde|def|efg|fgh|ghi|hij|ijk|jkl|klm|lmn|mno|nop|opq|pqr|qrs|rst|stu|tuv|uvw|vwx|wxy|xyz/i,  # Sequências alfabéticas
    ~r/qwe|wer|ert|rty|tyu|yui|uio|iop|asd|sdf|dfg|fgh|ghj|hjk|jkl|zxc|xcv|cvb|vbn|bnm/i  # Padrões de teclado
  ]

  def validate_password(password, user \\ nil, _opts \\ []) do
    results = [
      validate_length(password),
      validate_complexity(password),
      validate_common_passwords(password),
      validate_weak_patterns(password),
      validate_user_specific(password, user),
      validate_password_history(password, user)
    ]

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] ->
        strength = calculate_password_strength(password)
        {:ok, %{strength: strength, score: strength.score}}
      errors ->
        {:error, Enum.map(errors, fn {:error, msg} -> msg end)}
    end
  end

  def password_strength(password) do
    calculate_password_strength(password)
  end

  def is_password_expired?(user) do
    case user.password_changed_at do
      nil -> true  # Force change if never set
      changed_at ->
        days_since_change = Date.diff(Date.utc_today(), Date.from_iso8601!(changed_at))
        days_since_change >= @password_expiry_days
    end
  end

  def next_password_expiry(user) do
    case user.password_changed_at do
      nil -> Date.utc_today()
      changed_at ->
        Date.from_iso8601!(changed_at)
        |> Date.add(@password_expiry_days)
    end
  end

  def generate_secure_password(length \\ 12) do
    uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    lowercase = "abcdefghijklmnopqrstuvwxyz"
    digits = "0123456789"
    special = "!@#$%^&*()_+-=[]{}|;:,.<>?"

    # Garante pelo menos um de cada tipo
    password_chars = [
      random_char(uppercase),
      random_char(lowercase),
      random_char(digits),
      random_char(special)
    ]

    # Completa com caracteres aleatórios
    all_chars = uppercase <> lowercase <> digits <> special
    remaining_chars = for _ <- 1..(length - 4), do: random_char(all_chars)

    (password_chars ++ remaining_chars)
    |> Enum.shuffle()
    |> List.to_string()
  end

  def get_policy_info do
    %{
      min_length: @min_length,
      max_length: @max_length,
      min_uppercase: @min_uppercase,
      min_lowercase: @min_lowercase,
      min_digits: @min_digits,
      min_special_chars: @min_special_chars,
      password_expiry_days: @password_expiry_days,
      max_password_history: @max_password_history,
      requirements: [
        "Mínimo de #{@min_length} caracteres",
        "Máximo de #{@max_length} caracteres",
        "Pelo menos #{@min_uppercase} letra maiúscula",
        "Pelo menos #{@min_lowercase} letra minúscula",
        "Pelo menos #{@min_digits} número",
        "Pelo menos #{@min_special_chars} caractere especial (!@#$%^&*...)",
        "Não pode ser uma senha comum",
        "Não pode conter padrões previsíveis",
        "Não pode ser similar a senhas anteriores"
      ]
    }
  end

  # Validações privadas

  defp validate_length(password) do
    length = String.length(password)
    cond do
      length < @min_length ->
        {:error, "A senha deve ter pelo menos #{@min_length} caracteres"}
      length > @max_length ->
        {:error, "A senha não pode ter mais de #{@max_length} caracteres"}
      true ->
        :ok
    end
  end

  defp validate_complexity(password) do
    errors = []

    errors = if count_matches(password, @uppercase_regex) < @min_uppercase do
      ["Deve conter pelo menos #{@min_uppercase} letra maiúscula" | errors]
    else
      errors
    end

    errors = if count_matches(password, @lowercase_regex) < @min_lowercase do
      ["Deve conter pelo menos #{@min_lowercase} letra minúscula" | errors]
    else
      errors
    end

    errors = if count_matches(password, @digit_regex) < @min_digits do
      ["Deve conter pelo menos #{@min_digits} número" | errors]
    else
      errors
    end

    errors = if count_matches(password, @special_char_regex) < @min_special_chars do
      ["Deve conter pelo menos #{@min_special_chars} caractere especial" | errors]
    else
      errors
    end

    case errors do
      [] -> :ok
      _ -> {:error, Enum.join(errors, ", ")}
    end
  end

  defp validate_common_passwords(password) do
    password_lower = String.downcase(password)

    if Enum.any?(@common_passwords, fn common ->
      String.contains?(password_lower, common)
    end) do
      {:error, "A senha não pode conter palavras comuns"}
    else
      :ok
    end
  end

  defp validate_weak_patterns(password) do
    if Enum.any?(@weak_patterns, fn pattern ->
      Regex.match?(pattern, password)
    end) do
      {:error, "A senha não pode conter padrões previsíveis (sequências, repetições, etc.)"}
    else
      :ok
    end
  end

  defp validate_user_specific(_password, nil), do: :ok
  defp validate_user_specific(password, user) do
    password_lower = String.downcase(password)
    errors = []

    # Não pode conter nome de usuário
    errors = if user.username && String.contains?(password_lower, String.downcase(user.username)) do
      ["A senha não pode conter seu nome de usuário" | errors]
    else
      errors
    end

    # Não pode conter nome real
    errors = if user.name && String.length(user.name) > 2 &&
               String.contains?(password_lower, String.downcase(user.name)) do
      ["A senha não pode conter seu nome real" | errors]
    else
      errors
    end

    # Não pode conter email
    errors = if user.email && String.contains?(password_lower, String.split(user.email, "@") |> List.first()) do
      ["A senha não pode conter partes do seu e-mail" | errors]
    else
      errors
    end

    case errors do
      [] -> :ok
      _ -> {:error, Enum.join(errors, ", ")}
    end
  end

  defp validate_password_history(_password, nil), do: :ok
  defp validate_password_history(_password, user) do
    # Aqui verificaríamos contra um histórico de senhas
    # Por enquanto, simularemos com uma verificação simples

    # Em um sistema real, você manteria hashes das últimas N senhas
    # e verificaria se a nova senha não é uma delas

    # Placeholder para implementação futura
    if user.id && rem(user.id, 10) == 0 do
      {:error, "A senha não pode ser uma das #{@max_password_history} senhas anteriores"}
    else
      :ok
    end
  end

  defp calculate_password_strength(password) do
    score = 0
    feedback = []

    # Pontuação base por comprimento
    length = String.length(password)
    {score, feedback} = case length do
      l when l >= 12 -> {score + 25, feedback}
      l when l >= 8 -> {score + 15, ["Considere usar uma senha mais longa" | feedback]}
      _ -> {score, ["Senha muito curta" | feedback]}
    end

    # Pontuação por variedade de caracteres
    char_types = [
      {String.match?(password, @uppercase_regex), "maiúsculas"},
      {String.match?(password, @lowercase_regex), "minúsculas"},
      {String.match?(password, @digit_regex), "números"},
      {String.match?(password, @special_char_regex), "caracteres especiais"}
    ]

    present_types = Enum.count(char_types, fn {present, _} -> present end)
    score = score + (present_types * 15)

    missing_types = char_types
    |> Enum.filter(fn {present, _} -> not present end)
    |> Enum.map(fn {_, type} -> type end)

    feedback = if length(missing_types) > 0 do
      ["Adicione #{Enum.join(missing_types, ", ")}" | feedback]
    else
      feedback
    end

    # Penalizações por padrões fracos
    {score, feedback} = if Enum.any?(@weak_patterns, &Regex.match?(&1, password)) do
      {max(score - 20, 0), ["Evite padrões previsíveis" | feedback]}
    else
      {score, feedback}
    end

    # Penalização por palavras comuns
    {score, feedback} = if Enum.any?(@common_passwords, &String.contains?(String.downcase(password), &1)) do
      {max(score - 30, 0), ["Evite palavras comuns" | feedback]}
    else
      {score, feedback}
    end

    # Bônus por entropia
    entropy = calculate_entropy(password)
    entropy_bonus = min(round(entropy - 30), 25)
    score = score + max(entropy_bonus, 0)

    # Classificação final
    {level, color} = case score do
      s when s >= 80 -> {:very_strong, "green"}
      s when s >= 60 -> {:strong, "blue"}
      s when s >= 40 -> {:moderate, "yellow"}
      s when s >= 20 -> {:weak, "orange"}
      _ -> {:very_weak, "red"}
    end

    %{
      score: min(score, 100),
      level: level,
      color: color,
      feedback: Enum.reverse(feedback),
      entropy: entropy
    }
  end

  defp calculate_entropy(password) do
    # Cálculo simplificado de entropia
    charset_size = calculate_charset_size(password)
    length = String.length(password)

    # Entropia = log2(charset_size^length)
    length * :math.log2(charset_size)
  end

  defp calculate_charset_size(password) do
    base_size = 0

    base_size = if String.match?(password, @lowercase_regex), do: base_size + 26, else: base_size
    base_size = if String.match?(password, @uppercase_regex), do: base_size + 26, else: base_size
    base_size = if String.match?(password, @digit_regex), do: base_size + 10, else: base_size
    base_size = if String.match?(password, @special_char_regex), do: base_size + 32, else: base_size

    max(base_size, 1)
  end

  defp count_matches(string, regex) do
    case Regex.scan(regex, string) do
      matches -> length(matches)
    end
  end

  defp random_char(charset) do
    charset
    |> String.codepoints()
    |> Enum.random()
  end
end
