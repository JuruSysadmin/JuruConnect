# Funcionalidade de Visualização de Arquivos - JuruConnect

## Visão Geral
A funcionalidade de Visualização de Arquivos permite que os usuários visualizem documentos diretamente na interface de chat sem precisar baixar ou abrir aplicativos externos. Isso melhora a experiência do usuário ao fornecer visualização instantânea de arquivos.

## Funcionalidades Implementadas

### 1. Integração do Visualizador de PDF
- **Tecnologia**: Integração PDF.js
- **Funcionalidades**:
  - Renderização completa de PDF no navegador
  - Navegação de página (anterior/próxima)
  - Controles de zoom (ampliar/reduzir)
  - Indicador de página mostrando página atual
  - Interface minimalista compatível com o design do chat

### 2. Renderização de Documentos do Office
- **Formatos Suportados**: Word (.doc/.docx), Excel (.xls/.xlsx), PowerPoint (.ppt/.pptx)
- **Tecnologia**: Integração Google Docs Viewer
- **Funcionalidades**:
  - Visualização inline usando iframe
  - Opção de download para funcionalidade completa
  - Mensagem de fallback para arquivos não suportados
  - Design de UI consistente

### 3. Visualizador de Imagens
- **Funcionalidades Aprimoradas**:
  - Clique para expandir em modal
  - Funcionalidade de zoom (ampliar/reduzir)
  - Atalhos de teclado (ESC para fechar, +/- para zoom)
  - Opção de download
  - Animações e transições suaves

### 4. Sobreposição de Sintaxe de Código
- **Linguagens Suportadas**: JavaScript, TypeScript, Python, Ruby, Go, Rust, Java, C++, CSS, HTML, PHP, Swift, Kotlin, Elixir, e mais
- **Funcionalidades**:
  - Sobreposição de sintaxe com suporte Prism.js
  - Funcionalidade de cópia para área de transferência
  - Opção de download
  - Tema escuro para melhor legibilidade
  - Detecção de linguagem por extensão de arquivo

### 5. Integração do Player de Vídeo
- **Funcionalidades**:
  - Player de vídeo HTML5 nativo
  - Controles de vídeo (play, pause, seek, volume)
  - Pré-carregamento de metadados para carregamento rápido
  - Opção de download
  - Design responsivo

### 6. Manipulador de Arquivo Genérico
- **Fallback para arquivos não suportados**:
  - Interface de download limpa
  - Exibição de informações de tipo de arquivo
  - Exibição de informações de tamanho de arquivo
  - UI consistente para todos os tipos de arquivo

## Implementação Técnica

### Mudanças no Banco de Dados
- **Migração**: `20251002201108_add_preview_fields_to_message_attachments.exs`
- **Novos Campos**:
  - `preview_capable`: Boolean indicando se o arquivo suporta visualização
  - `language`: String para detecção de linguagem de arquivo de código
  - `metadata`: Mapa JSON para informações adicionais do arquivo

### Arquitetura de Componentes
- **Componente Principal**: `AppWeb.FilePreview.file_preview/1`
- **Sub-componentes**:
  - `pdf_preview/1` - Visualizador de documento PDF
  - `office_preview/1` - Visualizador de documento do Office
  - `image_preview/1` - Visualizador de imagem aprimorado
  - `video_preview/1` - Player de vídeo
  - `code_preview/1` - Sobrepositor de sintaxe de código
  - `generic_preview/1` - Manipulador de fallback

### Hooks JavaScript
- **FilePreviewHook**: Hook principal para inicializar todos os componentes de visualização
- **CopyCodeHook**: Gerencia cópia de código para área de transferência
- **DownloadProgressHook**: Fornece feedback de progresso de download
- **VirtualScrollHook**: Scroll virtual opcional para arquivos grandes

### Detecção de Tipo de Arquivo
O sistema detecta automaticamente tipos de arquivo baseado em:
- Tipo MIME do arquivo carregado
- Análise da extensão do arquivos
- Aprimoramento progressivo para capacidades de visualização

## Pontos de Integração

### Integração com ChatLive
- **Importação**: Adicionado `import AppWeb.FilePreview` ao ChatLive
- **Manipuladores de Eventos**:
  - `toggle_preview` - Mostrar/ocultar visualizações inline
  - `download_file` - Manipular downloads de arquivo
  - `copy_code` - Copiar conteúdo de código para área de transferência
- **Atualização do Template**: Substituído previews de imagem estáticos por componentes de visualização de arquivo dinâmicos

### Integração JavaScript
- **Arquivo**: `assets/js/hooks/file_preview_hook.js`
- **Registro**: Adicionado todos os hooks ao `app.js` principal
- **Dependências**: PDF.js carregado dinamicamente do CDN

## Experiência do Usuário

### Filosofia de Design
- **Minimalista**: Interfaces limpas que não distraem do fluxo do chat
- **Consistente**: Todos os componentes de visualização seguem os mesmos padrões de design
- **Responsivo**: Funciona em desktop, tablet e mobile
- **Acessível**: Navegação por teclado e suporte a leitores de tela

### Padrões de Interação
- **Visualização Inline**: Arquivos aparecem como cartões de visualização dentro das mensagens do chat
- **Expandível**: Clique para abrir modo tela cheia/visualização
- **Progressivo**: Funcionalidade básica sempre disponível, funcionalidades aprimoradas carregam progressivamente
- **Fallback**: Degradação graciosa para arquivos não suportados

## Compatibilidade com Navegadores
- **Navegadores Modernos**: Suporte completo de funcionalidades
- **Aprimoramento Progressivo**: Funcionalidade básica em navegadores antigos
- **Mobile**: Interfaces adequadas para toque com escala apropriada

## Considerações de Performance
- **Carregamento Sob Demanda**: PDF.js e outras bibliotecas carregadas quando necessário
- **CDN**: Bibliotecas externas servidas do CDN para carregamento mais rápido
- **Cache**: Conteúdo de visualização cacheado para melhor performance
- **Responsivo**: Carregamento adaptativo baseado no tamanho e tipo do arquivo

## Considerações de Segurança
- **Validação de Arquivo**: Validação de tipo MIME antes da geração da visualização
- **Sandboxing**: Documentos do Office renderizados em iframe sandbox
- **CORS**: Compartilhamento de Recursos de Origem Cruzada apropriado para visualizadores externos
- **Proteção XSS**: Sanitização de conteúdo para arquivos carregados

## Aprimoramentos Futuros
- **Funcionalidades Avançadas de PDF**: Busca de texto, suporte a anotações
- **Edição do Office**: Funcionalidades básicas de edição para documentos do Office
- **Funcionalidades Colaborativas**: Visualização colaborativa em tempo real
- **Otimização Mobile**: Aprimoramento de gestos de toque para visualização mobile
- **Geração de Miniaturas**: Geração automática de miniaturas para carregamento mais rápido

## Considerações de Teste
- **Testes Unitários**: Testar detecção de tipo de arquivo e renderização de componentes
- **Testes de Integração**: Testar carregamento de visualização e interação
- **Testes de Navegador**: Teste de compatibilidade entre navegadores
- **Testes de Performance**: Teste de carga com vários tamanhos de arquivo

## Notas de Manutenção
- **Atualizações de Dependências**: Atualizações regulares do PDF.js e outras bibliotecas externas
- **Atualizações de Segurança**: Monitorar atualizações de segurança em dependências externas
- **Monitoramento de Performance**: Rastrear tempos de carregamento e interações do usuário
- **Manipulação de Erro**: Manipulação robusta de erro para visualizações com falha

A funcionalidade de Visualização de Arquivos melhora significativamente a experiência de chat do JuruConnect ao fornecer capacidades de visualização de documentos perfeitas diretamente na interface de chat, reduzindo mudanças de contexto e melhorando a produtividade para usuários compartilhando arquivos com conteúdo de apoio.
