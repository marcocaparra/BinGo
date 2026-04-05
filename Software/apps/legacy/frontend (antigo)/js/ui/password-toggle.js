/**
@param {string} inputId
@param {string} toggleId
 */
function setupPasswordToggle(inputId, toggleId) {
    const passwordInput = document.getElementById(inputId);
    const toggleButton = document.getElementById(toggleId);

    if (!passwordInput || !toggleButton) {
        console.warn("Elementos do toggle de senha não encontrados:", inputId, toggleId);
        return;
    }

    const eyeIcon = toggleButton.querySelector('.icon-eye');
    const eyeOffIcon = toggleButton.querySelector('.icon-eye-off');

    toggleButton.addEventListener("click", () => {
        const isPassword = passwordInput.type === "password";

        passwordInput.type = isPassword ? "text" : "password";

        eyeIcon.toggleAttribute('hidden', isPassword);
        eyeOffIcon.toggleAttribute('hidden', !isPassword);
    });
}

export { setupPasswordToggle };