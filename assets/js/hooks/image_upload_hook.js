const ImageUploadHook = {
  mounted() {
    this.setupDragAndDrop();
    this.setupVisualFeedback();
    this.setupFileInput();
  },

  setupDragAndDrop() {
    const input = this.el;
    const container = input.closest('form') || input.parentElement;
    const messageInput = container.querySelector('#message-input');

    // Prevent default drag behaviors
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
      container.addEventListener(eventName, this.preventDefaults, false);
    });

    // Handle dropped files
    container.addEventListener('drop', (e) => {
      this.handleDroppedFiles(e);
    }, false);

    // Visual feedback for drag over
    container.addEventListener('dragenter', (e) => {
      this.showDragOverlay();
      if (messageInput) {
        messageInput.classList.add('border-blue-400', 'bg-blue-50/50');
      }
    }, false);

    container.addEventListener('dragleave', (e) => {
      // Only hide if leaving the entire container
      if (!container.contains(e.relatedTarget)) {
        this.hideDragOverlay();
        if (messageInput) {
          messageInput.classList.remove('border-blue-400', 'bg-blue-50/50');
        }
      }
    }, false);

    // Reset input styling on drop
    container.addEventListener('drop', (e) => {
      if (messageInput) {
        messageInput.classList.remove('border-blue-400', 'bg-blue-50/50');
      }
    }, false);
  },

  setupVisualFeedback() {
    const container = this.el.closest('form') || this.el.parentElement;
    this.dragOverlay = container.querySelector('#drag-overlay');
  },

  setupFileInput() {
    // Listen for file input changes (when user clicks to select file)
    this.el.addEventListener('change', (e) => {
      if (e.target.files.length > 0) {
        const files = Array.from(e.target.files);
        
        // Validate files
        const validFiles = files.filter(file => {
          if (!file.type.startsWith('image/')) {
            this.showError('Por favor, selecione apenas arquivos de imagem (JPG, PNG, GIF, etc.)');
            return false;
          }
          
          if (file.size > 5 * 1024 * 1024) {
            this.showError('Arquivo muito grande. Máximo permitido: 5MB');
            return false;
          }
          
          return true;
        });
        
        if (validFiles.length === 0) {
          e.target.value = ''; // Clear the input
          return;
        }
        
        // Transfer files to LiveView input
        this.transferFilesToLiveView(validFiles);
        
      }
    });
  },

  transferFilesToLiveView(files) {
    // Try different selectors for LiveView input
    let liveViewInput = document.querySelector('input[data-phx-upload]');
    if (!liveViewInput) {
      liveViewInput = document.querySelector('input[phx-upload]');
    }
    if (!liveViewInput) {
      liveViewInput = document.querySelector('input[data-phx-hook]');
    }
    if (!liveViewInput) {
      // Try to find input with accept="image/*" that's not our drag-drop input
      liveViewInput = document.querySelector('input[type="file"][accept*="image"]:not(#drag-drop-input)');
    }

    if (liveViewInput) {
      // Create a new FileList with all files
      const dataTransfer = new DataTransfer();
      files.forEach(file => {
        dataTransfer.items.add(file);
      });
      
      // Set the files to the LiveView input
      liveViewInput.files = dataTransfer.files;
      
      // Trigger change event to notify LiveView
      const changeEvent = new Event('change', { bubbles: true });
      liveViewInput.dispatchEvent(changeEvent);
      
    }
  },

  transferFileToLiveView(file) {
    // Keep this method for backward compatibility
    this.transferFilesToLiveView([file]);
  },

  preventDefaults(e) {
    e.preventDefault();
    e.stopPropagation();
  },

  showDragOverlay() {
    if (this.dragOverlay) {
      const content = this.dragOverlay.querySelector('#drag-content');
      
      // Show overlay with animation
      this.dragOverlay.classList.remove('opacity-0', 'pointer-events-none');
      this.dragOverlay.classList.add('opacity-100', 'drag-overlay-active');
      
      // Animate content
      if (content) {
        content.classList.remove('scale-95');
        content.classList.add('scale-100', 'drag-content-active');
      }
      
      // Add haptic feedback if available
      if (navigator.vibrate) {
        navigator.vibrate(50);
      }
    }
  },

  hideDragOverlay() {
    if (this.dragOverlay) {
      const content = this.dragOverlay.querySelector('#drag-content');
      
      // Remove animation classes
      this.dragOverlay.classList.remove('drag-overlay-active');
      if (content) {
        content.classList.remove('drag-content-active', 'scale-100');
        content.classList.add('scale-95');
      }
      
      // Hide overlay after animation
      setTimeout(() => {
        this.dragOverlay.classList.remove('opacity-100');
        this.dragOverlay.classList.add('opacity-0', 'pointer-events-none');
      }, 150);
    }
  },

  handleDroppedFiles(e) {
    const dt = e.dataTransfer;
    const files = dt.files;

    if (files.length > 0) {
      // Check if files are images
      const imageFiles = Array.from(files).filter(file => {
        return file.type.startsWith('image/');
      });

      if (imageFiles.length > 0) {
        // Validate all image files
        const validFiles = imageFiles.filter(file => {
          if (file.size > 5 * 1024 * 1024) {
            this.showError('Arquivo muito grande. Máximo permitido: 5MB');
            return false;
          }
          return true;
        });

        if (validFiles.length === 0) {
          this.hideDragOverlay();
          return;
        }

        // Limit to 3 files maximum
        const filesToUpload = validFiles.slice(0, 3);
        
        if (validFiles.length > 3) {
          this.showError('Máximo de 3 imagens permitidas. Apenas as primeiras 3 serão enviadas.');
        }

        // Show success animation before hiding
        this.showSuccessAnimation();
        
        // Transfer files to LiveView input
        this.transferFilesToLiveView(filesToUpload);
        
      } else {
        this.hideDragOverlay();
        this.showError('Por favor, solte apenas arquivos de imagem (JPG, PNG, GIF, etc.)');
      }
    } else {
      this.hideDragOverlay();
    }
  },

  showSuccessAnimation() {
    if (this.dragOverlay) {
      const content = this.dragOverlay.querySelector('#drag-content');
      
      if (content) {
        // Change to success state
        content.innerHTML = `
          <div class="text-center relative">
            <div class="relative mb-6">
              <div class="w-20 h-20 bg-gradient-to-br from-green-500 to-green-600 rounded-full flex items-center justify-center mx-auto shadow-xl">
                <svg class="w-10 h-10 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                </svg>
              </div>
              <!-- Partículas de sucesso -->
              <div class="success-particles">
                <div class="success-particle"></div>
                <div class="success-particle"></div>
                <div class="success-particle"></div>
                <div class="success-particle"></div>
                <div class="success-particle"></div>
                <div class="success-particle"></div>
                <div class="success-particle"></div>
                <div class="success-particle"></div>
              </div>
            </div>
            <h3 class="text-xl font-bold text-gray-800 mb-2">Imagem adicionada!</h3>
            <p class="text-sm text-gray-600">Processando upload...</p>
          </div>
        `;
        
        // Add success animation
        content.classList.add('animate-pulse');
        
        // Hide after success animation
        setTimeout(() => {
          this.hideDragOverlay();
        }, 1500);
      }
    }
  },

  showError(message) {
    // Create or update error message
    let errorDiv = document.querySelector('.upload-error');
    if (!errorDiv) {
      errorDiv = document.createElement('div');
      errorDiv.className = 'upload-error text-red-600 text-sm mt-2 p-2 bg-red-50 border border-red-200 rounded';
      this.el.parentElement.appendChild(errorDiv);
    }
    errorDiv.textContent = message;
    
    // Auto-hide after 5 seconds
    setTimeout(() => {
      if (errorDiv) {
        errorDiv.remove();
      }
    }, 5000);
  }
};

export default ImageUploadHook;

