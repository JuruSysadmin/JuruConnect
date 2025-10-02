const ThemeHook = {
  mounted() {
    this.applyTheme();
    this.setupThemeListener();
  },

  updated() {
    this.applyTheme();
  },

  applyTheme() {
    const theme = this.el.dataset.theme;
    if (!theme) return;

    try {
      const themeData = JSON.parse(theme);
      this.applyThemeStyles(themeData);
    } catch (error) {
      console.error('Erro ao aplicar tema:', error);
    }
  },

  applyThemeStyles(theme) {
    // Aplicar variáveis CSS customizadas
    const root = document.documentElement;
    
    // Cores
    root.style.setProperty('--primary-color', theme.primary_color || '#3B82F6');
    root.style.setProperty('--secondary-color', theme.secondary_color || '#10B981');
    root.style.setProperty('--accent-color', theme.accent_color || '#F59E0B');
    root.style.setProperty('--background-color', theme.background_color || '#FFFFFF');
    
    // Tipografia
    root.style.setProperty('--font-family', theme.font_family || 'Inter, system-ui, sans-serif');
    
    // Layout
    root.style.setProperty('--border-radius', this.getBorderRadius(theme.border_radius));
    root.style.setProperty('--animation-speed', this.getAnimationSpeed(theme.animation_speed));
    root.style.setProperty('--message-density', this.getMessageDensity(theme.message_density));
    
    // Aplicar fundo
    this.applyBackground(theme);
    
    // Aplicar modo escuro/claro
    this.applyThemeMode(theme.theme_mode);
    
    // Aplicar densidade compacta
    this.applyCompactMode(theme.compact_mode);
  },

  applyBackground(theme) {
    const body = document.body;
    const chatContainer = document.querySelector('.chat-container');
    
    if (!chatContainer) return;
    
    // Remover classes de fundo anteriores
    chatContainer.classList.remove('theme-background-gradient', 'theme-background-solid', 'theme-background-image');
    
    switch (theme.background_type) {
      case 'gradient':
        chatContainer.classList.add('theme-background-gradient');
        if (theme.background_gradient) {
          chatContainer.style.background = theme.background_gradient;
        }
        break;
        
      case 'solid':
        chatContainer.classList.add('theme-background-solid');
        chatContainer.style.backgroundColor = theme.background_color;
        break;
        
      case 'image':
        if (theme.wallpaper_url) {
          chatContainer.classList.add('theme-background-image');
          chatContainer.style.backgroundImage = `url('${theme.wallpaper_url}')`;
          chatContainer.style.backgroundSize = 'cover';
          chatContainer.style.backgroundPosition = 'center';
          chatContainer.style.backgroundRepeat = 'no-repeat';
          chatContainer.style.opacity = theme.wallpaper_opacity || 0.1;
        }
        break;
    }
  },

  applyThemeMode(themeMode) {
    const body = document.body;
    
    // Remover classes de tema anteriores
    body.classList.remove('theme-light', 'theme-dark');
    
    if (themeMode === 'dark') {
      body.classList.add('theme-dark');
    } else {
      body.classList.add('theme-light');
    }
  },

  applyCompactMode(compactMode) {
    const body = document.body;
    
    if (compactMode) {
      body.classList.add('theme-compact');
    } else {
      body.classList.remove('theme-compact');
    }
  },

  getBorderRadius(borderRadius) {
    switch (borderRadius) {
      case 'none': return '0px';
      case 'small': return '4px';
      case 'medium': return '8px';
      case 'large': return '16px';
      default: return '8px';
    }
  },

  getAnimationSpeed(animationSpeed) {
    switch (animationSpeed) {
      case 'slow': return '0.5s';
      case 'normal': return '0.3s';
      case 'fast': return '0.1s';
      default: return '0.3s';
    }
  },

  getMessageDensity(messageDensity) {
    switch (messageDensity) {
      case 'compact': return '0.5rem';
      case 'comfortable': return '1rem';
      case 'spacious': return '1.5rem';
      default: return '1rem';
    }
  },

  setupThemeListener() {
    // Escutar eventos de atualização de tema
    this.handleEvent('theme-updated', (data) => {
      console.log('Tema atualizado:', data);
      // Recarregar tema se necessário
      setTimeout(() => {
        this.applyTheme();
      }, 100);
    });
  }
};

export default ThemeHook;
