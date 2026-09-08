// All screenshots and installation steps remain available without JavaScript.
const tabList = document.querySelector('.view-tabs');
const tabs = [...tabList.querySelectorAll('button')];
const panels = tabs.map(tab => document.getElementById(tab.dataset.panel));

function selectTab(index, focus = false) {
  tabs.forEach((tab, i) => {
    tab.setAttribute('aria-selected', String(i === index));
    tab.tabIndex = i === index ? 0 : -1;
    panels[i].hidden = i !== index;
  });
  if (focus) tabs[index].focus();
}

tabList.setAttribute('role', 'tablist');
tabs.forEach((tab, i) => {
  tab.setAttribute('role', 'tab');
  tab.setAttribute('aria-controls', panels[i].id);
  panels[i].setAttribute('role', 'tabpanel');
  panels[i].setAttribute('aria-labelledby', tab.id);
  tab.addEventListener('click', () => selectTab(i));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (i + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (i - 1 + tabs.length) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next === undefined) return;
    event.preventDefault();
    selectTab(next, true);
  });
});
selectTab(0);
tabList.hidden = false;

function revealLinkedSection() {
  const section = document.getElementById(location.hash.slice(1));
  if (section instanceof HTMLDetailsElement) section.open = true;
}
window.addEventListener('hashchange', revealLinkedSection);
revealLinkedSection();

const status = document.getElementById('copy-status');
document.querySelectorAll('.copy').forEach(button => {
  button.hidden = false;
  let resetTimer;
  button.addEventListener('click', async () => {
    const command = document.getElementById(button.dataset.target);
    clearTimeout(resetTimer);
    try {
      await navigator.clipboard.writeText(command.textContent);
      button.textContent = 'Copied';
      status.textContent = 'Command copied.';
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(command);
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = 'Select and copy the command manually; clipboard access is unavailable.';
    }
    resetTimer = window.setTimeout(() => { button.textContent = 'Copy'; }, 1800);
  });
});
