// Auto-dismiss toasts after 4s
document.querySelectorAll('.toast').forEach(t => setTimeout(() => t.remove(), 4000));
