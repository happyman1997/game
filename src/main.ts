import './ui/style.css';
import { App } from './ui/app';

const app = new App(document.getElementById('app')!);
app.boot().catch((e) => {
  console.error(e);
  document.getElementById('app')!.innerHTML = `<div class="fatal">Ошибка запуска: ${String(e?.message ?? e)}</div>`;
});
