// Crisp HTML labels pinned to 3D positions.
import { Vector3 } from 'three';

export class Labels {
  constructor(root) {
    this.root = root;
    this.items = [];
    this.v = new Vector3();
  }

  add(text, cls) {
    const el = document.createElement('div');
    el.className = `lbl ${cls}`;
    const span = document.createElement('span');
    span.textContent = text;
    el.appendChild(span);
    el.style.display = 'none';
    this.root.appendChild(el);
    const item = { el, span, pos: new Vector3(), visible: true, opacity: 1, shown: false, text };
    this.items.push(item);
    return item;
  }

  setText(item, text) {
    if (item.text === text) return;
    item.text = text;
    item.span.textContent = text;
  }

  update(camera, w, h) {
    const v = this.v;
    for (const it of this.items) {
      let show = it.visible && it.opacity > 0.02;
      if (show) {
        v.copy(it.pos).project(camera);
        show = v.z < 1 && v.z > -1 && v.x > -1.15 && v.x < 1.15 && v.y > -1.15 && v.y < 1.2;
        if (show) {
          const x = ((v.x + 1) / 2) * w;
          const y = ((1 - v.y) / 2) * h;
          it.el.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,0)`;
          const o = it.opacity.toFixed(2);
          if (it._o !== o) {
            it.el.style.opacity = o;
            it._o = o;
          }
        }
      }
      if (show !== it.shown) {
        it.el.style.display = show ? 'block' : 'none';
        it.shown = show;
      }
    }
  }
}
