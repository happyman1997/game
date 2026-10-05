// Шрифты встроены в игру: она работает без интернета.
import '@fontsource/cormorant-garamond/500.css';
import '@fontsource/cormorant-garamond/600.css';
import '@fontsource/cormorant-garamond/700.css';
import '@fontsource/pt-serif/400.css';
import '@fontsource/pt-serif/400-italic.css';
import '@fontsource/pt-serif/700.css';
import './ui/style.css';
import { App } from './ui/app';

const app = new App(document.getElementById('app')!);
app.boot().catch((e) => {
  console.error(e);
  document.getElementById('app')!.innerHTML = `<div class="fatal">Ошибка запуска: ${String(e?.message ?? e)}</div>`;
});
