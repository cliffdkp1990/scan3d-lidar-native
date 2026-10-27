Object.defineProperty(window,'indexedDB',{configurable:true,get(){throw new DOMException('Synthetic storage denial','SecurityError');}});
