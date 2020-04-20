document.addEventListener("DOMContentLoaded", () => {
	const refreshImages = async () => {
		const res = await fetch("/api/");
		if (!res.ok) {
			throw res;
		}
		const images = await res.json();

		const imagesElement = document.querySelector("#images");
		while (imagesElement.firstChild) {
			imagesElement.removeChild(imagesElement.lastChild);
		}

		images.forEach((image) => {
			const img = new Image(); 
			img.src = image;
			imagesElement.appendChild(img);
		});
	};

	refreshImages();

	const handlePost = async (file) => {
		const dataRes = await fetch("/api/sign_post");
		if (!dataRes.ok) {
			throw dataRes;
		}
		const data = await dataRes.json();

		const formData = new FormData();
		formData.append("Content-Type", file.type);
		Object.entries(data.fields).forEach(([k, v]) => {
			formData.append(k, v);
		});
		formData.append("file", file);

		const postRes = await fetch(data.url, {
			method: "POST",
			body: formData,
		});

		if (!postRes.ok) {
			throw postRes;
		}
		refreshImages();
	};

	const element = document.querySelector("#post");
	element.addEventListener("change", async (event) => {
		const files = event.currentTarget.files;
		if (files.length) {
			try {
				await handlePost(files[0]);
			}catch (e) {
				console.error(e);
			}
		}
	});
});

