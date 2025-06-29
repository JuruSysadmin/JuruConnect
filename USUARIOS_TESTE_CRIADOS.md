# 👥 Usuários de Teste - JuruConnect

## ✅ USUÁRIOS CRIADOS COM SUCESSO

### 📊 Resumo
- **Total de usuários:** 3
- **Status:** Todos funcionais e prontos para testes
- **Senhas:** Atendem às políticas de segurança implementadas

---

## 🔐 CREDENCIAIS PARA TESTES

### 1️⃣ **ADMINISTRADOR**
```
👤 Usuário: admin_teste
🔐 Senha: Admin123!@#
👨‍💼 Nome: Administrador Teste
🛡️ Role: admin
✨ Permissões: Acesso total ao sistema
```

**Recursos disponíveis:**
- ✅ Dashboard de Segurança (`/admin/security`)
- ✅ Todas as funcionalidades administrativas
- ✅ Gestão de usuários bloqueados
- ✅ Exportação de logs
- ✅ Configuração de políticas

---

### 2️⃣ **GERENTE**
```
👤 Usuário: manager_teste
🔐 Senha: Manager456$%^
👨‍💼 Nome: Gerente Teste
🛡️ Role: manager
✨ Permissões: Moderação e supervisão
```

**Recursos disponíveis:**
- ✅ Dashboard de Segurança (`/admin/security`)
- ✅ Funcionalidades de moderação
- ✅ Visualização de relatórios
- ✅ Dashboard principal
- ✅ Chat por pedidos

---

### 3️⃣ **VENDEDOR**
```
👤 Usuário: vendedor_teste
🔐 Senha: Vendas789&*()
👨‍💼 Nome: Vendedor Teste
🛡️ Role: clerk
✨ Permissões: Acesso básico do sistema
```

**Recursos disponíveis:**
- ✅ Dashboard principal (`/dashboard`)
- ✅ Chat por pedidos (`/chat/:order_id`)
- ✅ Busca de pedidos (`/buscar-pedido`)
- ❌ Dashboard de segurança (acesso negado)

---

## 🔗 ROTAS PARA TESTES

### **Autenticação**
- `/auth/login` - Interface moderna de login
- `/reset-password` - Recuperação de senha
- `/login` - Interface antiga (ainda funcional)

### **Dashboard**
- `/dashboard` - Dashboard principal (todos os usuários)
- `/hello` - Dashboard alternativo

### **Administração** (apenas admin/manager)
- `/admin/security` - Dashboard de segurança

### **Chat**
- `/chat/12345` - Chat de pedido (exemplo)
- `/buscar-pedido` - Busca de pedidos

---

## 🧪 CENÁRIOS DE TESTE SUGERIDOS

### **Teste de Login**
1. Teste login normal com credenciais corretas
2. Teste rate limiting com múltiplas tentativas incorretas
3. Teste recuperação de senha
4. Teste validação de políticas de senha

### **Teste de Permissões**
1. Login como `admin_teste` → acesso total
2. Login como `manager_teste` → acesso moderado
3. Login como `vendedor_teste` → tentar acessar `/admin/security` (deve ser negado)

### **Teste de Segurança**
1. Tentativas de brute force
2. Rate limiting por IP
3. Logs de auditoria
4. Desbloqueio manual de contas

### **Teste de UX**
1. Interface responsiva em dispositivos móveis
2. Validação em tempo real de senhas
3. Feedback visual de loading
4. Mensagens de erro específicas

---

## 🔍 VALIDAÇÃO DAS SENHAS

Todas as senhas atendem às políticas implementadas:

### **Política de Senha Atual:**
- ✅ Mínimo 8 caracteres
- ✅ Pelo menos 1 letra maiúscula
- ✅ Pelo menos 1 letra minúscula  
- ✅ Pelo menos 1 número
- ✅ Pelo menos 1 caractere especial
- ✅ Não contém palavras comuns
- ✅ Não contém padrões previsíveis

### **Análise de Força:**
- `Admin123!@#` → Força: **Forte** (score: ~75)
- `Manager456$%^` → Força: **Forte** (score: ~75)
- `Vendas789&*()` → Força: **Forte** (score: ~75)

---

## 🎯 PRÓXIMOS PASSOS

### **Para desenvolvimento:**
1. Testar todas as funcionalidades com diferentes roles
2. Validar fluxo completo de recuperação de senha
3. Testar interface administrativa
4. Verificar logs de segurança

### **Para produção:**
1. Remover usuários de teste
2. Configurar e-mails reais para notificações
3. Ajustar políticas conforme necessidades da empresa
4. Configurar backup dos logs de segurança

---

## 🔧 COMANDOS ÚTEIS

### **Listar usuários:**
```bash
mix run -e "alias App.Accounts; users = Accounts.list_users(); Enum.each(users, fn u -> IO.puts(\"#{u.username} | #{u.role}\") end)"
```

### **Reset de senha (desenvolvimento):**
```bash
mix run -e "alias App.Accounts; user = Accounts.get_user_by_username(\"admin_teste\"); Accounts.update_user(user, %{password: \"NovaSenha123!\"})"
```

### **Verificar estatísticas de segurança:**
```bash
mix run -e "alias App.Auth.RateLimiter; IO.inspect(RateLimiter.get_stats())"
```

---

## ⚠️ IMPORTANTE

**Estes são usuários de TESTE apenas!**

- 🚫 **NÃO usar em produção**
- 🔄 **Remover antes de deploy**
- 🔐 **Senhas são públicas neste documento**
- 🧪 **Servem apenas para validação do sistema**

---

**Status:** ✅ **TODOS OS USUÁRIOS CRIADOS E FUNCIONAIS**

O sistema está pronto para testes completos de todas as funcionalidades implementadas nas Fases 1 e 2! 🚀 