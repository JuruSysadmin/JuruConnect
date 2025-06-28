/**
 * @fileoverview Funções de interação para o formulário de login
 * @author JuruConnect Team
 * @version 1.0.0
 */

/**
 * Alterna a visibilidade da senha entre texto e oculto
 * Gerencia os ícones de olho para mostrar o estado atual
 * @function togglePassword
 * @global
 */
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

/**
 * Controla a visibilidade do sufixo de domínio baseado no input do usuário
 * Mostra ou oculta o sufixo "@domain.com" dependendo se há texto no campo
 * @function toggleDomainSuffix
 * @global
 */
function toggleDomainSuffix() {
    const appleIdInput = document.getElementById('appleId');
    const domainSuffix = document.getElementById('domainSuffix');
    
    if (appleIdInput.value.length > 0) {
        domainSuffix.style.display = 'block';
    } else {
        domainSuffix.style.display = 'none';
    }
}

/**
 * Manipula o envio do formulário de login
 * Previne o envio padrão e exibe dados do formulário
 * @function handleSubmit
 * @global
 * @param {Event} event - Evento de submit do formulário
 */
function handleSubmit(event) {
    event.preventDefault();
    const appleId = document.getElementById('appleId').value;
    const password = document.getElementById('password').value;
    
    alert('Login form submitted! Check console for details.');
} 