const AWS = require("aws-sdk");
const util = require("util");

const s3 = new AWS.S3({
	signatureVersion: "v4",
});

const getRandomFilename = () =>	require("crypto").randomBytes(16).toString("hex");

exports.handler = async (event) => {
	if (event.path === "/") {
		// does not handle pagination, only for demonstration
		const objects = await s3.listObjectsV2({Bucket: process.env.BUCKET}).promise();
		const contents = objects.Contents.map(({Key}) => {
			return `/api/image/${Key}`;
		});

		return {
			statusCode: 200,
			headers: {
				"Content-Type": "application/json",
			},
			body: JSON.stringify(contents),
		};
	} else if (event.path === "/sign_post") {
		const data = await util.promisify(s3.createPresignedPost.bind(s3))({
			Bucket: process.env.BUCKET,
			Fields: {
				key: getRandomFilename(),
			},
			Conditions: [
				["starts-with", "$Content-Type", "image/"],
			]
		});

		data.url = `/${process.env.PATH_PART}/`;

		return {
			statusCode: 200,
			headers: {
				"Content-Type": "application/json",
			},
			body: JSON.stringify(data),
		};
	}else if (event.path.startsWith("/image/")) {
		const imagePath = event.path.match(/^\/image\/(?<image>.*)$/).groups.image;

		const url = await s3.getSignedUrlPromise("getObject", {Bucket: process.env.BUCKET, Key: imagePath});

		const parsed = new URL(url);
		const cfUrl = `/${process.env.PATH_PART}${parsed.pathname}${parsed.search}`;
		return {
			statusCode: 303,
			headers: {
				Location: cfUrl,
			},
		};
	}else {
		return {
			statusCode: 404,
		};
	}
};
