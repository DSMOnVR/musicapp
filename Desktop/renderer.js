const audio = document.getElementById("audio");
let library = { tracks: [], playlists: [] }, currentIndex = -1, currentView = "all";
const $ = id => document.getElementById(id);
const fmt = n => { if (!Number.isFinite(n)) return "0:00"; const m=Math.floor(n/60),s=Math.floor(n%60); return m+":"+String(s).padStart(2,"0"); };
async function init(){ library=await window.dsm.getLibrary(); render(); }
function visibleTracks(){
 const q=$("search").value.toLowerCase().trim();
 return library.tracks.filter(t => currentView==="all" || (currentView==="artists" && t.artist) || (currentView==="albums" && t.album))
 .filter(t=>!q || [t.title,t.artist,t.album].join(" ").toLowerCase().includes(q));
}
function render(){
 $("songCount").textContent=library.tracks.length+" songs in your collection";
 $("empty").classList.toggle("hide",library.tracks.length>0);
 $("trackList").innerHTML="";
 visibleTracks().forEach((t)=>{
  const index=library.tracks.findIndex(x=>x.id===t.id), row=document.createElement("div"); row.className="track";
  row.innerHTML='<div class="track-art">♫</div><div><b></b><small></small></div><div><small></small></div><small class="filetype"></small><button title="Remove song">•••</button>';
  row.querySelectorAll("b,small")[0].textContent=t.title; row.querySelectorAll("small")[0].textContent=t.artist||"Unknown Artist";
  row.querySelectorAll("small")[1].textContent=t.album||"Unknown Album";
  row.querySelector(".filetype").textContent=(t.file.split(".").pop()||"AUDIO").toUpperCase();
  row.querySelector("button").onclick=async e=>{e.stopPropagation();if(confirm("Remove this song from DSM Music?")){library=await window.dsm.removeTrack(t.id);render();}};
  row.onclick=()=>play(index); $("trackList").appendChild(row);
 });
 $("viewTitle").textContent=currentView==="all"?"All songs":currentView[0].toUpperCase()+currentView.slice(1);
 $("sectionTitle").textContent=currentView==="all"?"Your library":currentView[0].toUpperCase()+currentView.slice(1);
}
async function play(index){
 if(index<0||index>=library.tracks.length)return;currentIndex=index;const t=library.tracks[index];
 audio.src=await window.dsm.audioUrl(t.file);audio.play().catch(()=>{});
 $("nowTitle").textContent=t.title;$("nowArtist").textContent=t.artist||"Unknown Artist";$("play").textContent="Ⅱ";
}
$("importBtn").onclick=$("emptyImport").onclick=async()=>{library=await window.dsm.importMusic();render();};
$("search").oninput=render;
document.querySelectorAll(".nav").forEach(b=>b.onclick=()=>{document.querySelectorAll(".nav").forEach(x=>x.classList.remove("active"));b.classList.add("active");currentView=b.dataset.view;render();});
$("play").onclick=()=>{if(!audio.src){if(library.tracks.length)play(0);return;}audio.paused?audio.play():audio.pause();};
audio.onplay=()=>$("play").textContent="Ⅱ";audio.onpause=()=>$("play").textContent="▶";
$("next").onclick=()=>play((currentIndex+1)%library.tracks.length);
$("prev").onclick=()=>play((currentIndex-1+library.tracks.length)%library.tracks.length);
audio.ontimeupdate=()=>{$("seek").value=audio.duration?audio.currentTime/audio.duration*100:0;$("elapsed").textContent=fmt(audio.currentTime);$("duration").textContent=fmt(audio.duration);};
audio.onended=()=>$("next").click();
$("seek").oninput=()=>{if(audio.duration)audio.currentTime=audio.duration*Number($("seek").value)/100;};
$("volume").oninput=()=>audio.volume=Number($("volume").value);
audio.volume=.8;
init();