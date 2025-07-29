function togglePassword() {
    const passwordInput = document.getElementById('password');
    const eyeOpen = document.getElementById('eyeOpen');
    const eyeCircle = document.getElementById('eyeCircle');
    const eyeSlash = document.getElementById('eyeSlash');

    if (passwordInput.type === 'password') {
        passwordInput.type = 'text';
        eyeOpen.style.display = 'none';
        eyeCircle.style.display = 'none';
        eyeSlash.style.display = 'block';
    } else {
        passwordInput.type = 'password';
        eyeOpen.style.display = 'block';
        eyeCircle.style.display = 'block';
        eyeSlash.style.display = 'none';
    }
}

function toggleDomainSuffix() {
    const appleIdInput = document.getElementById('appleId');
    const domainSuffix = document.getElementById('domainSuffix');

    if (appleIdInput.value.length > 0) {
        domainSuffix.style.display = 'block';
    } else {
        domainSuffix.style.display = 'none';
    }
}

function handleSubmit(event) {
    event.preventDefault();
    const appleId = document.getElementById('apple-id').value;
    const password = document.getElementById('password').value;

    // Simulate login process
    if (appleId && password) {
      // Show loading state
      const submitButton = document.querySelector('button[type="submit"]');
      const originalText = submitButton.textContent;
      submitButton.textContent = 'Entrando...';
      submitButton.disabled = true;

      // Simulate API call
      setTimeout(() => {
        // Reset button
        submitButton.textContent = originalText;
        submitButton.disabled = false;

        // Show success message
        showMessage('Login realizado com sucesso!', 'success');
      }, 2000);
    } else {
      showMessage('Por favor, preencha todos os campos.', 'error');
    }
}