defmodule App.Repo.Migrations.ListTreaties do
  use Ecto.Migration

  def change do
    # Criar algumas tratativas de exemplo para testar a busca
    execute """
    INSERT INTO treaties (id, treaty_code, title, description, status, priority, created_by, store_id, inserted_at, updated_at)
    VALUES
      (gen_random_uuid(), 'TRT000001', 'Negociação de Contrato Principal', 'Tratativa para negociação do contrato principal da empresa', 'active', 'high', (SELECT id FROM users LIMIT 1), (SELECT store_id FROM users LIMIT 1), NOW(), NOW()),
      (gen_random_uuid(), 'TRT000002', 'Renovação de Parceria', 'Discussão sobre renovação da parceria comercial', 'active', 'normal', (SELECT id FROM users LIMIT 1), (SELECT store_id FROM users LIMIT 1), NOW(), NOW()),
      (gen_random_uuid(), 'TRT000003', 'Acordo de Fornecimento', 'Negociação de acordo de fornecimento de produtos', 'active', 'normal', (SELECT id FROM users LIMIT 1), (SELECT store_id FROM users LIMIT 1), NOW(), NOW())
    ON CONFLICT (treaty_code) DO NOTHING;
    """
  end
end
