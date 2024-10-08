import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { GROUPS, type ItemGroupType, type ItemType } from './data';
import "./App.css";
import github_svg from './github-mark.svg';
import zig_svg from './zig-mark.svg';
import sokol_logo from './logo_s_large.png';
const BASE_URL = import.meta.env.BASE_URL;

function Item(props: ItemType) {
  return (<div className="item">
    <a href={`${BASE_URL}wasm/${props.name}.html`}>
      {props.name}
      <figure>
        <img width={150} height={78} src={`${BASE_URL}wasm/${props.name}.jpg`} />
      </figure>
    </a>

    <ul className="small">
      {props.links.map((link, i) => {
        const [name, url] = link;
        return (<li key={i}>
          <a href={url} target="_blank">
            {"🔗"}{name}
          </a>
        </li>);
      })}
    </ul>
  </div>);
}

function Group(props: ItemGroupType) {
  return (<>
    <div className="item orange">
      {props.url
        ? <a href={props.url} target="_blank">{"🔗"}{props.name}</a>
        : props.name
      }
    </div>
    {props.items.map((props, i) => <Item key={i} {...props} />)}
  </>);
}

function Home() {
  return (<>
    <div className="container">

      <div className="item">
        <a href="https://github.com/ousttrue/zig-sokol-sample">
          <img width={150} src={github_svg} />
        </a>
      </div>

      <div className="item">
        <a href="https://floooh.github.io/sokol-html5/">
          <img width={150} src={sokol_logo} />
        </a>
      </div>

      <div className="item">
        <a href="https://github.com/floooh/sokol-zig">
          <img width={75} src={sokol_logo} />
          <img width={75} src={zig_svg} />
        </a>
      </div>

      {GROUPS.map((props, i) => <Group key={i} {...props} />)}
    </div>
  </>);
}

function Page404() {
  return (<>
    <div className="not_found">
      <div>404 not found</div>
    </div>
  </>);
}

function App() {
  return (
    <>
      <BrowserRouter basename={BASE_URL}>
        <Routes>
          <Route index element={<Home />} />
          <Route path="*" element={<Page404 />} />
        </Routes>
      </BrowserRouter>
    </>
  )
}

export default App
