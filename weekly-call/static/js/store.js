// ── Cart (localStorage) ───────────────────────────────────────────────────────
function getCart() {
  try { return JSON.parse(localStorage.getItem('shopdb_cart') || '[]'); } catch { return []; }
}
function saveCart(cart) {
  localStorage.setItem('shopdb_cart', JSON.stringify(cart));
  updateCartUI();
}
function clearCart() {
  localStorage.removeItem('shopdb_cart');
  updateCartUI();
}

function addToCart(id, name, price, img, showToastMsg = true) {
  const cart = getCart();
  const existing = cart.find(i => i.id === id);
  if (existing) { existing.qty++; }
  else { cart.push({ id, name, price: parseFloat(price), img, qty: 1 }); }
  saveCart(cart);
  if (showToastMsg) showToast(`"${name}" added to cart`);
}

function removeFromCart(id) {
  saveCart(getCart().filter(i => i.id !== id));
}

function changeQtyInCart(id, delta) {
  const cart = getCart();
  const item = cart.find(i => i.id === id);
  if (!item) return;
  item.qty = Math.max(1, item.qty + delta);
  saveCart(cart);
}

// ── Cart UI ───────────────────────────────────────────────────────────────────
function updateCartUI() {
  const cart = getCart();
  const total = cart.reduce((s, i) => s + i.qty, 0);
  const subtotal = cart.reduce((s, i) => s + i.price * i.qty, 0);

  document.querySelectorAll('#cartCount').forEach(el => el.textContent = total);
  document.querySelectorAll('#drawerCount').forEach(el => el.textContent = total);

  const cartItems = document.getElementById('cartItems');
  const cartSubtotal = document.getElementById('cartSubtotal');
  const cartTotal = document.getElementById('cartTotal');
  const checkoutBtn = document.getElementById('checkoutBtn');

  if (cartSubtotal) cartSubtotal.textContent = '$' + subtotal.toFixed(2);
  if (cartTotal)    cartTotal.textContent    = '$' + subtotal.toFixed(2);
  if (checkoutBtn) {
    checkoutBtn.style.pointerEvents = cart.length ? 'all' : 'none';
    checkoutBtn.style.opacity = cart.length ? '1' : '0.4';
  }

  if (!cartItems) return;
  if (!cart.length) {
    cartItems.innerHTML = `<div class="cart-empty"><i class="fa-solid fa-bag-shopping"></i><span>Your cart is empty</span></div>`;
    return;
  }
  cartItems.innerHTML = cart.map(item => `
    <div class="cart-item">
      <div class="cart-item-img">
        ${item.img ? `<img src="${item.img}" alt="${item.name}"/>` : '📦'}
      </div>
      <div class="cart-item-info">
        <div class="cart-item-name">${item.name}</div>
        <div class="cart-item-price">$${item.price.toFixed(2)} each</div>
        <div class="cart-item-controls">
          <div class="cart-item-qty">
            <button onclick="changeQtyInCart(${item.id},-1)">−</button>
            <span>${item.qty}</span>
            <button onclick="changeQtyInCart(${item.id},1)">+</button>
          </div>
          <button class="cart-item-remove" onclick="removeFromCart(${item.id})">
            <i class="fa-solid fa-trash"></i> Remove
          </button>
          <span style="margin-left:auto;font-weight:600;font-size:13.5px">$${(item.price*item.qty).toFixed(2)}</span>
        </div>
      </div>
    </div>
  `).join('');
}

// ── Cart drawer ───────────────────────────────────────────────────────────────
function toggleCart() {
  const overlay = document.getElementById('cartOverlay');
  const drawer  = document.getElementById('cartDrawer');
  const isOpen  = drawer.classList.contains('open');
  overlay.classList.toggle('open', !isOpen);
  drawer.classList.toggle('open', !isOpen);
  document.body.style.overflow = isOpen ? '' : 'hidden';
}

// ── Toast ─────────────────────────────────────────────────────────────────────
let toastTimer;
function showToast(msg) {
  const el = document.getElementById('storeToast');
  if (!el) return;
  el.innerHTML = `<i class="fa-solid fa-circle-check"></i> ${msg}`;
  el.style.display = 'flex';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.style.display = 'none'; }, 2800);
}

// ── Init ──────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', updateCartUI);
