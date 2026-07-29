const panel = document.getElementById('panel');
const categories = document.getElementById('categories');
const options = document.getElementById('options');
const mainScreen = document.getElementById('main-screen');
const optionsScreen = document.getElementById('options-screen');
const stylesScreen = document.getElementById('styles-screen');
const styleList = document.getElementById('style-list');
const styleSummary = document.getElementById('style-summary');
const subtitle = document.getElementById('subtitle');
const priceOutputs = document.querySelectorAll('.price-output');
const scaleKey = 'rsg_weaponcomp_ui_scale';
const scaleInput = document.getElementById('scale');
const scaleValue = document.getElementById('scale-value');
const cameraZoom = document.getElementById('camera-zoom');
const cameraZoomValue = document.getElementById('camera-zoom-value');
const modal = document.getElementById('modal');
const modalTitle = document.getElementById('modal-title');
const modalMessage = document.getElementById('modal-message');
const modalInput = document.getElementById('modal-input');
const modalCancel = document.getElementById('modal-cancel');
const modalConfirm = document.getElementById('modal-confirm');
const guideOverlay = document.getElementById('guide-overlay');
const guideContent = document.getElementById('guide-content');
let state = { categories: [], price: '0.00' };
let activeCategoryKey = null;
let activeComponentKey = null;
let selectedStyleId = null;
let navigationItems = [];
let navigationIndex = 0;
let pivoting = false;
let lastX = 0;
let lastY = 0;
let modalAction = null;
let guideOpen = false;

const post = (name, data = {}) => fetch(`https://${GetParentResourceName()}/${name}`, { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data) });

function closeModal() {
  modal.classList.add('hidden');
  modalInput.classList.add('hidden');
  modalInput.value = '';
  modalAction = null;
}

function openModal({ title, message, confirmLabel = 'Confirm', confirmClass = '', input = false, placeholder = '', onConfirm }) {
  modalTitle.textContent = title;
  modalMessage.textContent = message;
  modalConfirm.textContent = confirmLabel;
  modalConfirm.className = `button ${confirmClass}`.trim();
  modalInput.classList.toggle('hidden', !input);
  modalInput.placeholder = placeholder;
  modalInput.value = '';
  modalAction = onConfirm;
  modal.classList.remove('hidden');
  (input ? modalInput : modalConfirm).focus();
}

function confirmModal() {
  if (!modalAction) return;
  const action = modalAction;
  const value = modalInput.classList.contains('hidden') ? null : modalInput.value.trim();
  if (!modalInput.classList.contains('hidden') && !value) {
    modalInput.focus();
    return;
  }
  closeModal();
  action(value);
}

function openStyleGuide() {
  guideOpen = true;
  closeModal();
  panel.classList.add('guide-hidden');
  guideOverlay.classList.remove('hidden');
  guideOverlay.setAttribute('aria-hidden', 'false');
  guideContent.scrollTop = 0;
  document.getElementById('guide-back-top').focus();
}

function closeStyleGuide() {
  guideOpen = false;
  guideOverlay.classList.add('hidden');
  guideOverlay.setAttribute('aria-hidden', 'true');
  panel.classList.remove('guide-hidden');
  renderStyles();
}
const savedScale = Math.max(.5, Math.min(1.5, Number(localStorage.getItem(scaleKey)) || 1));
scaleInput.value = savedScale;
scaleValue.textContent = `${Math.round(savedScale * 100)}%`;
document.documentElement.style.setProperty('--ui-scale', savedScale);
cameraZoom.addEventListener('input', () => {
  cameraZoomValue.textContent = `${cameraZoom.value}%`;
  post('weaponcomp:zoom', { zoom: Number(cameraZoom.value) });
});
scaleInput.addEventListener('input', () => {
  const value = Number(scaleInput.value);
  localStorage.setItem(scaleKey, value);
  scaleValue.textContent = `${Math.round(value * 100)}%`;
  document.documentElement.style.setProperty('--ui-scale', value);
});
function recalculateScaleLimit() {
  if (panel.getAttribute('aria-hidden') === 'true') return;
  const widthLimit = (innerWidth * .94) / panel.offsetWidth;
  const heightLimit = (innerHeight * .94) / panel.offsetHeight;
  const max = Math.max(.5, Math.min(2, Math.floor(Math.min(widthLimit, heightLimit) / .05) * .05));
  scaleInput.max = max.toFixed(2);
  if (Number(scaleInput.value) > max) {
    scaleInput.value = max;
    scaleValue.textContent = `${Math.round(max * 100)}%`;
    localStorage.setItem(scaleKey, max);
    document.documentElement.style.setProperty('--ui-scale', max);
  }
}

function selectNavigationItem(index) {
  if (!navigationItems.length) return;
  navigationItems.forEach(item => item.element.classList.remove('keyboard-selected'));
  navigationIndex = (index + navigationItems.length) % navigationItems.length;
  const item = navigationItems[navigationIndex];
  item.element.classList.add('keyboard-selected');
  if (item.key) activeComponentKey = item.key;
  if (item.styleId) selectStyle(item.styleId);
  item.element.scrollIntoView({ block: 'nearest' });
}

function setNavigationItems(items, preferredKey) {
  navigationItems = items;
  const preferred = preferredKey
    ? items.findIndex(item => item.key === preferredKey || Number(item.styleId) === Number(preferredKey))
    : -1;
  selectNavigationItem(preferred >= 0 ? preferred : 0);
}

function renderMain() {
  categories.innerHTML = '';
  const mainItems = [];
  (state.categories || []).forEach(category => {
    const button = document.createElement('button');
    button.className = 'category';
    button.innerHTML = `${category.label}<small>${category.count} group${category.count === 1 ? '' : 's'}</small>`;
    button.onclick = () => { activeComponentKey = null; post('weaponcomp:category', { key: category.key }); renderOptions(category); };
    button.onmouseenter = () => selectNavigationItem(mainItems.findIndex(item => item.element === button));
    categories.appendChild(button);
    mainItems.push({ element: button, activate: () => button.click() });
  });
  const stylesButton = document.createElement('button');
  stylesButton.className = 'category';
  stylesButton.innerHTML = `Saved Styles<small>${(state.styles || []).length} saved</small>`;
  stylesButton.onclick = () => { activeCategoryKey = 'styles'; activeComponentKey = null; renderStyles(); };
  stylesButton.onmouseenter = () => selectNavigationItem(mainItems.findIndex(item => item.element === stylesButton));
  categories.appendChild(stylesButton);
  mainItems.push({ element: stylesButton, activate: () => stylesButton.click() });
  if (state.canPickup) {
    const pickupButton = document.createElement('button');
    pickupButton.className = 'category pickup-action';
    pickupButton.innerHTML = 'Pickup<small>Pack up this workbench</small>';
    pickupButton.onclick = () => post('weaponcomp:pickup');
    pickupButton.onmouseenter = () => selectNavigationItem(mainItems.findIndex(item => item.element === pickupButton));
    categories.appendChild(pickupButton);
    mainItems.push({ element: pickupButton, activate: () => pickupButton.click() });
  }
  const mainBuy = mainScreen.querySelector('.buy-action');
  mainItems.push({ element: mainBuy, activate: () => mainBuy.click() });
  setNavigationItems(mainItems);
  priceOutputs.forEach(output => { output.textContent = `$${state.price || '0.00'}`; });
  const zoom = Number(state.cameraZoom) || 50;
  cameraZoom.value = zoom;
  cameraZoomValue.textContent = `${zoom}%`;
}

function selectStyle(styleId) {
  selectedStyleId = styleId == null ? null : Number(styleId);
  document.querySelectorAll('.style-item').forEach(button => {
    button.classList.toggle('selected', Number(button.dataset.styleId) === selectedStyleId);
  });
  const style = (state.styles || []).find(item => Number(item.id) === selectedStyleId);
  styleSummary.textContent = style
    ? `${style.compatible} compatible · ${style.unsupported} unsupported · ${style.invalid} invalid`
    : 'Select a saved style.';
  if (style) styleSummary.textContent = `${style.compatible} compatible | ${style.unsupported} unsupported | ${style.invalid} invalid`;
  document.querySelectorAll('.style-needs-selection').forEach(button => { button.disabled = !style; });
}

function renderStyles() {
  activeCategoryKey = 'styles';
  subtitle.textContent = 'Saved Styles';
  styleList.innerHTML = '';
  const items = [];
  const guideButton = document.getElementById('style-guide');
  items.push({ element: guideButton, activate: () => guideButton.click() });
  const styles = state.styles || [];
  if (selectedStyleId && !styles.some(style => Number(style.id) === Number(selectedStyleId))) selectedStyleId = null;
  styles.forEach(style => {
    const button = document.createElement('button');
    button.className = 'style-item';
    button.dataset.styleId = style.id;
    const label = document.createElement('span');
    label.textContent = style.name;
    const detail = document.createElement('small');
    detail.textContent = `${style.compatible} compatible`;
    button.append(label, detail);
    button.onclick = () => selectNavigationItem(items.findIndex(item => item.element === button));
    button.onmouseenter = button.onclick;
    styleList.appendChild(button);
    items.push({ element: button, styleId: style.id, activate: () => selectStyle(style.id) });
  });
  ['style-create', 'style-load', 'style-update', 'style-add-missing', 'style-remove', 'styles-back'].forEach(id => {
    const button = document.getElementById(id);
    items.push({ element: button, activate: () => button.click() });
  });
  const stylesBuy = stylesScreen.querySelector('.buy-action');
  items.push({ element: stylesBuy, activate: () => stylesBuy.click() });
  mainScreen.classList.add('hidden');
  optionsScreen.classList.add('hidden');
  stylesScreen.classList.remove('hidden');
  setNavigationItems(items, selectedStyleId);
  selectStyle(selectedStyleId);
}

function renderOptions(category) {
  activeCategoryKey = category.key;
  subtitle.textContent = category.label;
  options.innerHTML = '';
  const optionItems = [];
  category.groups.forEach(group => {
    const row = document.createElement('div');
    row.className = 'component-group';
    const heading = document.createElement('div');
    heading.className = 'component-heading';
    const label = document.createElement('span');
    label.textContent = group.label;
    const controls = document.createElement('div');
    controls.className = 'selector-controls';
    const previous = document.createElement('button');
    previous.className = 'selector-arrow';
    previous.textContent = '‹';
    const value = document.createElement('span');
    previous.textContent = '<';
    value.className = 'component-value';
    const next = document.createElement('button');
    next.className = 'selector-arrow';
    next.textContent = '›';
    let selectedIndex = group.currentIndex || 1;
    next.textContent = '>';
    const cleanValue = optionLabel => {
      const text = String(optionLabel || '');
      const configuredPrefixes = (state.metalList && state.metalList[group.key]) || [];
      const removable = new Set(
        String(group.label || '').toLowerCase().split(/\s+/)
          .concat(['part', 'color', 'material', 'tint', 'metal', 'engraving'])
          .concat(configuredPrefixes.map(prefix => String(prefix).toLowerCase()))
      );
      const words = text.trim().split(/\s+/);
      while (words.length > 1 && removable.has(words[0].toLowerCase())) words.shift();
      return words.join(' ');
    };
    const showValue = () => {
      const selected = group.options[selectedIndex - 1];
      value.textContent = selected ? cleanValue(selected.label) : '';
    };
    const move = direction => {
      activeComponentKey = group.key;
      selectedIndex = ((selectedIndex - 1 + direction + group.count) % group.count) + 1;
      showValue();
      post('weaponcomp:select', { group: category.key, component: group.key, index: selectedIndex });
    };
    previous.onclick = () => move(-1);
    next.onclick = () => move(1);
    row.onmouseenter = () => selectNavigationItem(optionItems.findIndex(item => item.element === row));
    heading.append(label);
    controls.append(previous, value, next);
    row.append(heading, controls);
    options.appendChild(row);
    optionItems.push({ element: row, key: group.key, previous, next });
    showValue();
  });
  const optionsBack = document.getElementById('back');
  const optionsBuy = optionsScreen.querySelector('.buy-action');
  optionItems.push({ element: optionsBack, activate: () => optionsBack.click() });
  optionItems.push({ element: optionsBuy, activate: () => optionsBuy.click() });
  setNavigationItems(optionItems, activeComponentKey);
  mainScreen.classList.add('hidden');
  optionsScreen.classList.remove('hidden');
  return;
  subtitle.textContent = category.label;
  options.innerHTML = '';
  category.options.forEach(item => {
    const button = document.createElement('button');
    button.className = `option${item.current ? ' current' : ''}`;
    button.innerHTML = `<span>${item.label}</span><span>${item.current ? '✓' : ''}</span>`;
    button.onclick = () => post('weaponcomp:select', { group: category.key, component: item.component, index: item.index });
    options.appendChild(button);
  });
  mainScreen.classList.add('hidden'); optionsScreen.classList.remove('hidden');
}

window.addEventListener('message', event => {
  const msg = event.data || {};
  if (msg.action === 'open' || msg.action === 'update') {
    if (msg.action === 'open') activeCategoryKey = null;
    state = msg.data || state; renderMain(); panel.setAttribute('aria-hidden','false'); recalculateScaleLimit();
    const activeCategory = (state.categories || []).find(category => category.key === activeCategoryKey);
    if (activeCategoryKey === 'styles') {
      renderStyles();
    } else if (activeCategory) {
      renderOptions(activeCategory);
    } else {
      mainScreen.classList.remove('hidden');
      optionsScreen.classList.add('hidden');
      stylesScreen.classList.add('hidden');
      subtitle.textContent = '';
    }
  } else if (msg.action === 'close') {
    closeModal();
    guideOpen = false;
    guideOverlay.classList.add('hidden');
    guideOverlay.setAttribute('aria-hidden', 'true');
    panel.classList.remove('guide-hidden');
    panel.setAttribute('aria-hidden','true');
  }
});
window.addEventListener('resize', recalculateScaleLimit);

document.getElementById('close').onclick = () => post('weaponcomp:close');
document.querySelectorAll('.buy-action').forEach(button => {
  button.onclick = () => openModal({
    title: 'Confirm Purchase',
    message: `Purchase these customizations for $${state.price || '0.00'}?`,
    confirmLabel: 'Buy',
    confirmClass: 'modal-confirm-buy',
    onConfirm: () => post('weaponcomp:buy'),
  });
});
const goBack = () => { activeCategoryKey = null; activeComponentKey = null; post('weaponcomp:back'); mainScreen.classList.remove('hidden'); optionsScreen.classList.add('hidden'); stylesScreen.classList.add('hidden'); subtitle.textContent = ''; renderMain(); };
document.getElementById('back').onclick = goBack;
document.getElementById('styles-back').onclick = goBack;
document.getElementById('style-guide').onclick = openStyleGuide;
document.getElementById('guide-back-top').onclick = closeStyleGuide;
document.getElementById('guide-back-bottom').onclick = closeStyleGuide;
document.getElementById('guide-close').onclick = () => post('weaponcomp:close');
document.getElementById('style-create').onclick = () => openModal({
  title: 'Save New Style',
  message: 'Enter a name for this weapon style.',
  confirmLabel: 'Save',
  confirmClass: 'modal-confirm-buy',
  input: true,
  placeholder: 'Style name',
  onConfirm: name => post('weaponcomp:styleCreate', { name }),
});
document.getElementById('style-load').classList.add('style-needs-selection');
document.getElementById('style-update').classList.add('style-needs-selection');
document.getElementById('style-add-missing').classList.add('style-needs-selection');
document.getElementById('style-remove').classList.add('style-needs-selection');
document.getElementById('style-load').onclick = () => { if (selectedStyleId) post('weaponcomp:styleLoad', { id: selectedStyleId }); };
document.getElementById('style-update').onclick = () => { if (selectedStyleId) post('weaponcomp:styleUpdate', { id: selectedStyleId }); };
document.getElementById('style-add-missing').onclick = () => { if (selectedStyleId) post('weaponcomp:styleAddMissing', { id: selectedStyleId }); };
document.getElementById('style-remove').onclick = () => {
  const style = (state.styles || []).find(item => Number(item.id) === Number(selectedStyleId));
  if (!style) return;
  openModal({
    title: 'Remove Saved Style',
    message: `Delete ${style.name}? This cannot be undone.`,
    confirmLabel: 'Remove',
    confirmClass: 'modal-confirm-danger',
    onConfirm: () => post('weaponcomp:styleRemove', { id: selectedStyleId }),
  });
};
modalCancel.onclick = closeModal;
modalConfirm.onclick = confirmModal;
document.addEventListener('keydown', event => {
  if (!modal.classList.contains('hidden')) {
    if (event.key === 'Escape' || (event.key === 'Backspace' && !event.target.matches('input, textarea'))) { event.preventDefault(); closeModal(); }
    else if (event.key === 'Enter') { event.preventDefault(); confirmModal(); }
    return;
  }
  if (guideOpen) {
    if (event.key === 'Escape') { event.preventDefault(); post('weaponcomp:close'); }
    else if (event.key === 'Backspace') { event.preventDefault(); closeStyleGuide(); }
    else if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
      event.preventDefault();
      guideContent.scrollBy({ top: event.key === 'ArrowUp' ? -90 : 90, behavior: 'smooth' });
    }
    return;
  }
  if (event.key === 'Escape') { post('weaponcomp:close'); return; }
  if (event.target.matches('input, textarea')) return;
  if (event.key === 'Backspace' && activeCategoryKey) {
    event.preventDefault();
    document.getElementById('back').click();
    return;
  }
  if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
    event.preventDefault();
    selectNavigationItem(navigationIndex + (event.key === 'ArrowUp' ? -1 : 1));
    return;
  }
  const selected = navigationItems[navigationIndex];
  if ((event.key === 'ArrowLeft' || event.key === 'ArrowRight') && selected) {
    const arrow = event.key === 'ArrowLeft' ? selected.previous : selected.next;
    if (arrow) { event.preventDefault(); arrow.click(); }
    return;
  }
  if (event.key === 'Enter' && selected && selected.activate) { event.preventDefault(); selected.activate(); }
});
document.addEventListener('mousedown', event => { if (event.button === 2) { pivoting=true; lastX=event.clientX; lastY=event.clientY; event.preventDefault(); } });
document.addEventListener('mouseup', event => { if (event.button === 2) pivoting=false; });
document.addEventListener('mousemove', event => { if (!pivoting) return; post('weaponcomp:pivot', { dx:event.clientX-lastX, dy:event.clientY-lastY }); lastX=event.clientX; lastY=event.clientY; });
document.addEventListener('contextmenu', event => event.preventDefault());
