const __vite__mapDeps=(i,m=__vite__mapDeps,d=(m.f||(m.f=["_astro/mermaid.core.KNiLNDYn.js","_astro/src.DaJp0K3q.js","_astro/chunk-Y2CYZVJY.DsF7k-Jl.js","_astro/preload-helper.CxFQXtKk.js","_astro/chunk-DU6HZSFF.C8KbwuuR.js","_astro/chunk-75Z2AOVW.rwv6v8XH.js","_astro/dist.CwJnzJJb.js","_astro/chunk-PWAF6VOD.DvKB0QbW.js","_astro/chunk-GMAD6QVW.Jow0KnSN.js","_astro/chunk-P2QGCYS3.Bp7w5MDi.js","_astro/chunk-4HAMMTFA.4sMoO5Va.js","_astro/rough.esm.Dy-Kn_BL.js","_astro/chunk-GVQU2GXP.Do5c4tGc.js","_astro/chunk-OSK3NFVY.BUfe8hEY.js","_astro/line.Br8hndvY.js","_astro/path.fybaL0A-.js","_astro/array.BifhSqXX.js","_astro/graphlib.DS17s2tU.js","_astro/chunk-L3NEJ4N5.CguSPYyG.js"])))=>i.map(i=>d[i]);
import{t as e}from"./preload-helper.CxFQXtKk.js";var t=(...e)=>console.error(`[astro-mermaid]`,...e),n=()=>document.querySelectorAll(`pre.mermaid`).length>0,r=null;async function i(){return r||(r=e(async()=>{let{default:e}=await import(`./mermaid.core.KNiLNDYn.js`);return{default:e}},__vite__mapDeps([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18])).then(async({default:e})=>{let t=[];if(t&&t.length>0){t.length;let n=t.map(e=>e.icons?{name:e.name,icons:e.icons}:{name:e.name,loader:()=>fetch(e.url).then(e=>e.json())});await e.registerIconPacks(n)}return e}).catch(e=>{throw t(`Failed to load mermaid:`,e),r=null,e}),r)}var a={startOnLoad:!1,theme:`default`},o={light:`default`,dark:`dark`};async function s(){let e=document.querySelectorAll(`pre.mermaid`);if(e.length,e.length===0)return;let n=await i(),r=a.theme;{let e=document.documentElement.getAttribute(`data-theme`),t=document.body.getAttribute(`data-theme`);r=o[e||t]||a.theme}n.initialize({...a,theme:r,gitGraph:{mainBranchName:`main`,showCommitLabel:!0,showBranches:!0,rotateCommitLabel:!0}});for(let r of e){if(r.hasAttribute(`data-processed`))continue;r.hasAttribute(`data-diagram`)||r.setAttribute(`data-diagram`,r.textContent||``);let e=r.getAttribute(`data-diagram`)||``,i=`mermaid-`+Math.random().toString(36).slice(2,11);try{let t=document.getElementById(i);t&&t.remove();let{svg:a}=await n.render(i,e);r.innerHTML=a,r.setAttribute(`data-processed`,`true`)}catch(e){t(`Mermaid rendering error for diagram:`,i,e);let n=document.createElement(`div`);n.style.cssText=`color: red; padding: 1rem; border: 1px solid red; border-radius: 0.5rem;`;let a=document.createElement(`strong`);a.textContent=`Error rendering diagram:`;let o=document.createElement(`span`);o.textContent=` `+(e.message||`Unknown error`),n.appendChild(a),n.appendChild(o),r.textContent=``,r.appendChild(n),r.setAttribute(`data-processed`,`true`)}}}n()&&s();{let e=new MutationObserver(e=>{for(let t of e)t.type===`attributes`&&t.attributeName===`data-theme`&&(document.querySelectorAll(`pre.mermaid[data-processed]`).forEach(e=>{e.removeAttribute(`data-processed`)}),s())});e.observe(document.documentElement,{attributes:!0,attributeFilter:[`data-theme`]}),e.observe(document.body,{attributes:!0,attributeFilter:[`data-theme`]})}document.addEventListener(`astro:after-swap`,()=>{n()&&s()});var c=document.createElement(`style`);c.textContent=`
            /* Prevent layout shifts by setting minimum height */
            pre.mermaid {
              display: flex;
              justify-content: center;
              align-items: center;
              margin: 2rem 0;
              padding: 1rem;
              background-color: transparent;
              border: none;
              overflow: auto;
              min-height: 200px; /* Prevent layout shift */
              position: relative;
            }
            
            /* Loading state with skeleton loader */
            pre.mermaid:not([data-processed]) {
              background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
              background-size: 200% 100%;
              animation: shimmer 1.5s infinite;
            }
            
            /* Dark mode skeleton loader */
            [data-theme="dark"] pre.mermaid:not([data-processed]) {
              background: linear-gradient(90deg, #2a2a2a 25%, #3a3a3a 50%, #2a2a2a 75%);
              background-size: 200% 100%;
            }
            
            @keyframes shimmer {
              0% {
                background-position: -200% 0;
              }
              100% {
                background-position: 200% 0;
              }
            }
            
            /* Show processed diagrams with smooth transition */
            pre.mermaid[data-processed] {
              animation: none;
              background: transparent;
              min-height: auto; /* Allow natural height after render */
            }
            
            /* Ensure responsive sizing for mermaid SVGs */
            pre.mermaid svg {
              max-width: 100%;
              height: auto;
            }
            
            /* Optional: Add subtle background for better visibility */
            @media (prefers-color-scheme: dark) {
              pre.mermaid[data-processed] {
                background-color: rgba(255, 255, 255, 0.02);
                border-radius: 0.5rem;
              }
            }
            
            @media (prefers-color-scheme: light) {
              pre.mermaid[data-processed] {
                background-color: rgba(0, 0, 0, 0.02);
                border-radius: 0.5rem;
              }
            }
            
            /* Respect user's color scheme preference */
            [data-theme="dark"] pre.mermaid[data-processed] {
              background-color: rgba(255, 255, 255, 0.02);
              border-radius: 0.5rem;
            }
            
            [data-theme="light"] pre.mermaid[data-processed] {
              background-color: rgba(0, 0, 0, 0.02);
              border-radius: 0.5rem;
            }
          `,document.head.appendChild(c);