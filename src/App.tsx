import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { GROUPS, type ItemGroupType, type ItemType } from './data';
import "./App.css";
import github_svg from './github-mark.svg';
const BASE_URL = import.meta.env.BASE_URL;

function Item(props: ItemType) {
  return (<div className="item">
    <a href={`${BASE_URL}wasm/${props.name}.html`}>
      {props.name}
      <figure>
        <img width={150} height={78} src={`${BASE_URL}wasm/${props.name}.jpg`} />
      </figure>
    </a>

    <ul>
      {props.links.map((link, i) => (
        <li key={i}>
          <a href={link.url} target="_blank">
            {"🔗"}{link.name}
          </a>
        </li>))}
    </ul>
  </div>);
}

function Group(props: ItemGroupType) {
  return (<>
    <div className="item">
      <a href={props.url} target="_blank">{"🔗"}{props.name}</a>
    </div>
    {props.items.map((props, i) => <Item key={i} {...props} />)}
  </>);
}

function Home() {
  return (<>
    <div className="container">
      <div className="item">
        <a href="https://github.com/ousttrue/zig-sokol-sample"><img width={150} src={github_svg} /></a>
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
