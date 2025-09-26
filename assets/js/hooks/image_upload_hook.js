const ImageUploadHook = {
  mounted() {
    console.log('ImageUploadHook mounted');
    this.setupDragAndDrop();
  },

  setupDragAndDrop() {
    const input = this.el;
    console.log('Setting up drag and drop for input:', input);

    // Prevent default drag behaviors
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
      input.addEventListener(eventName, this.preventDefaults, false);
    });

    // Handle dropped files
    input.addEventListener('drop', (e) => {
      console.log('Drop event on input');
      this.handleDroppedFiles(e);
    }, false);
  },

  preventDefaults(e) {
    e.preventDefault();
    e.stopPropagation();
  },

  handleDroppedFiles(e) {
    console.log('handleDroppedFiles called on input');
    const dt = e.dataTransfer;
    const files = dt.files;

    console.log('Files dropped on input:', files.length);

    if (files.length > 0) {
      // Check if files are images
      const imageFiles = Array.from(files).filter(file => {
        console.log('File type:', file.type, 'is image:', file.type.startsWith('image/'));
        return file.type.startsWith('image/');
      });

      console.log('Image files found:', imageFiles.length);

      if (imageFiles.length > 0) {
        // Use the first image file
        const file = imageFiles[0];
        console.log('Processing file:', file.name, 'size:', file.size);
        
        // Check file size (5MB limit)
        if (file.size > 5 * 1024 * 1024) {
          alert('Arquivo muito grande. Máximo permitido: 5MB');
          return;
        }

        // Create a new FileList with the dropped file
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(file);
        
        // Set the files to the input
        this.el.files = dataTransfer.files;
        
        // Trigger change event to notify LiveView
        const changeEvent = new Event('change', { bubbles: true });
        this.el.dispatchEvent(changeEvent);

        console.log('File dropped and added to upload input:', file.name);
      } else {
        alert('Por favor, solte apenas arquivos de imagem (JPG, PNG, GIF, etc.)');
      }
    }
  }
};

export default ImageUploadHook;
